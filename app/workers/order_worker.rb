# frozen_string_literal: true

require_relative "base_worker"
require_relative "../models/order"

module Analytics
  module Workers
    # Writes an order event into the analytics Postgres warehouse and
    # updates the rolling inventory-velocity counter.
    #
    # Locks acquired IN THIS ORDER:
    #
    #   1. OrderLock       (serializes writes to the orders rollup)
    #   2. InventoryLock   (serializes the inventory-velocity counter)
    class OrderWorker < BaseWorker
      sidekiq_options queue: :orders, retry: 5

      def perform(payload)
        # Ensure payload has order_id before processing
        unless payload.is_a?(Hash) && (payload.key?(:order_id) || payload.key?("order_id"))
          logger.error("OrderWorker received payload missing 'order_id' key. Raising error to trigger Sidekiq retry/dead-letter.", payload: payload)
          raise ArgumentError, "Payload missing required 'order_id' key"
        end

        begin
          # Ensure the payload has symbol keys for the Order model which expects symbols
          symbolized_payload = payload.each_with_object({}) { |(k, v), h| h[k.to_sym] = v }
          order = Analytics::Models::Order.from_payload(symbolized_payload)
        rescue KeyError => e
          logger.error("OrderWorker payload missing required key: #{e.message}", payload: payload)
          raise ArgumentError, "Payload missing required key"
        end

        lock.with_locks("OrderLock", "InventoryLock") do
          persist_order_event(order)
          bump_inventory_velocity(order)
        end
      end

      private

      def persist_order_event(order)
        db do |conn|
          conn.exec_params(
            "INSERT INTO order_events (order_id, user_id, total_cents, item_count, placed_at) " \
            "VALUES ($1, $2, $3, $4, $5) ON CONFLICT (order_id) DO NOTHING",
            [order.id, order.user_id, order.total_cents, order.item_count, order.placed_at]
          )
        end
      end

      def bump_inventory_velocity(order)
        # Per-SKU velocity counter, used by the catalog team to spot
        # trending products. Shares the InventoryLock so concurrent
        # payment refunds don't race with this update.
        db do |conn|
          order.items.each do |item|
            sku = item["sku"] || item[:sku]
            unless sku
              logger.warn("Skipping item with missing sku", item: item)
              next
            end
            qty = item.fetch("quantity", 1)
            conn.exec_params(
              "INSERT INTO inventory_velocity (sku, delta, reason) VALUES ($1, $2, 'order')",
              [sku, qty]
            )
          end
        end
      end
    end
  end
end

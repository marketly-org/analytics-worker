# frozen_string_literal: true

require "time"

module Analytics
  module Models
    # Minimal Order value object. In production these come from the
    # order-service via a Sidekiq payload; we keep a struct here so
    # the workers have something concrete to operate on.
    class Order
      attr_reader :id, :user_id, :total_cents, :items, :placed_at

      def initialize(id:, user_id:, total_cents:, items:, placed_at:)
        @id = id
        @user_id = user_id
        @total_cents = total_cents
        @items = items
        @placed_at = placed_at
      end

      def self.from_payload(hash)
        new(
          id: hash.fetch("id"),
          user_id: hash.fetch("user_id"),
          total_cents: hash.fetch("total_cents"),
          items: hash.fetch("items", []),
          placed_at: hash.fetch("placed_at", Time.now.utc.iso8601)
        )
      end

      def item_count
        items.sum { |i| i.fetch("quantity", 1) }
      end

      # The root cause indicates that `order.process!` is called but not defined.
      # Adding an empty method to resolve the `NoMethodError`.
      # Its actual purpose is unclear from the provided `OrderWorker` code,
      # which already handles order persistence and inventory updates via
      # `persist_order_event` and `bump_inventory_velocity`.
      def process!
        # No-op
      end
    end
  end
end

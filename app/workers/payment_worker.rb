# frozen_string_literal: true

require_relative "base_worker"

module Analytics
  module Workers
    # Writes a payment event (charge, refund, chargeback) into the
    # analytics warehouse and updates the inventory-velocity counter
    # so refunds decrement the trending-product signal.
    #
    # ------------------------------------------------------------------
    # BUG: This worker acquires locks in the WRONG ORDER.
    #
    #   OrderWorker acquires:   OrderLock   ->  InventoryLock
    #   PaymentWorker acquires: InventoryLock  ->  OrderLock   (WRONG)
    #
    # Under concurrent load, OrderWorker holds OrderLock and blocks
    # waiting for InventoryLock at the same time PaymentWorker holds
    # InventoryLock and blocks waiting for OrderLock. Neither side can
    # make progress, so both Sidekiq jobs eventually hit the lock-acquire
    # timeout and fail. Retries pile up, Redis fills with retry payloads,
    # and the worker pods OOMKilled under the heap pressure.
    #
    # FIX: Acquire the locks in the same order as OrderWorker —
    # OrderLock THEN InventoryLock. Replace the line
    #
    #     lock.with_locks("InventoryLock", "OrderLock") do
    #
    # with
    #
    #     lock.with_locks("OrderLock", "InventoryLock") do
    # ------------------------------------------------------------------
    class PaymentWorker < BaseWorker
      sidekiq_options queue: :payments, retry: 5

      def perform(payload)
        event = symbolize(payload)

        # BUG: lock order is reversed relative to OrderWorker.
        lock.with_locks("InventoryLock", "OrderLock") do
          persist_payment_event(event)
          adjust_inventory_velocity(event)
        end
      end

      private

      def persist_payment_event(event)
        db do |conn|
          conn.exec_params(
            "INSERT INTO payment_events (payment_id, order_id, user_id, amount_cents, kind) " \
            "VALUES ($1, $2, $3, $4, $5) ON CONFLICT (payment_id) DO NOTHING",
            [event[:payment_id], event[:order_id], event[:user_id],
             event[:amount_cents], event[:kind]]
          )
        end
      end

      # A refund should decrement the velocity counter for every SKU in
      # the linked order. We touch the InventoryLock here for the same
      # reason OrderWorker does — to keep the counter consistent.
      def adjust_inventory_velocity(event)
        return unless event[:kind] == "refund"

        db do |conn|
          res = conn.exec_params(
            "SELECT items FROM order_events WHERE order_id = $1",
            [event[:order_id]]
          )
          return if res.ntuples.zero?

          items = JSON.parse(res.field_values("items").first)
          items.each do |item|
            sku = item.fetch("sku")
            qty = item.fetch("quantity", 1)
            conn.exec_params(
              "INSERT INTO inventory_velocity (sku, delta, reason) VALUES ($1, $2, 'refund')",
              [sku, -qty]
            )
          end
        end
      end

      def symbolize(hash)
        hash.each_with_object({}) { |(k, v), h| h[k.to_sym] = v }
      end
    end
  end
end

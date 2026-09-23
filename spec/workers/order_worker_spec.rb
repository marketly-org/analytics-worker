# frozen_string_literal: true

require "spec_helper"
require_relative "../../app/workers/order_worker"

module Analytics
  module Workers
    RSpec.describe OrderWorker do
      let(:payload) do
        {
          "id" => "ord_123",
          "user_id" => "usr_1",
          "total_cents" => 4_999,
          "items" => [{ "sku" => "SKU-1", "quantity" => 2 }],
          "placed_at" => "2026-01-01T00:00:00Z"
        }
      end

      # We stub out the DB + lock layers and assert that the worker
      # calls them in the expected order. This is a structural test —
      # the concurrency bug only manifests under real Redis contention,
      # which is out of scope for unit tests.
      let(:lock_order) { [] }

      before do
        stub_const("Analytics::DB", double("DB").as_null_object)
        stub_lock = double("Lock")
        allow(stub_lock).to receive(:with_locks) do |*names, &block|
          lock_order.concat(names)
          block.call
        end
        allow(described_class).to receive(:lock).and_return(stub_lock)
      end

      it "persists the order event and returns" do
        expect { described_class.new.perform(payload) }.not_to raise_error
      end

      it "acquires OrderLock before InventoryLock" do
        described_class.new.perform(payload)
        expect(lock_order).to eq(%w[OrderLock InventoryLock])
      end

      context "with a multi-item order" do
        let(:payload) do
          super().merge("items" => [
            { "sku" => "SKU-1", "quantity" => 1 },
            { "sku" => "SKU-2", "quantity" => 3 }
          ])
        end

        it "bumps velocity for every item" do
          conn = double("PG::Connection")
          allow(Analytics::DB).to receive(:with) { |&blk| blk.call(conn) }
          allow(conn).to receive(:exec_params)

          described_class.new.perform(payload)

          # 1 insert into order_events + 2 inserts into inventory_velocity
          expect(conn).to have_received(:exec_params).exactly(3).times
        end
      end
    end
  end
end

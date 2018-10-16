require 'spec_helper'

module RemoteLock::Adapters
  describe Redis do
    it_behaves_like 'a remote lock adapter', redis

    context "Redis scope" do
      let(:adapter) { Redis.new(redis) }
      let(:uid)      { '1234' }
      let(:test_key) { "test_key" }

      before do
        adapter.stub(:uid).and_return(uid)
      end

      describe "#store" do
        it "should store the lock in redis" do
          redis.get(test_key).should be_nil
          adapter.store(test_key, 100)
          redis.get(test_key).should eq uid
        end

        it 'return truthy on success' do
          adapter.store(test_key, 100).should be(true)
        end

        it 'return falsy on failure' do
          redis.set(test_key, uid)
          adapter.store(test_key, 100).should be(false)
        end

        context "expiry" do
          it "should expire the key after the time is over" do
            adapter.store(test_key, 1)
            sleep 1.1
            redis.exists(test_key).should be(false)
          end

          it "should expire the key after the time is over" do
            adapter.store(test_key, 10)
            sleep 0.5
            redis.exists(test_key).should be(true)
          end
        end
      end

      describe "#has_key?" do
        it "should return true if the key exists in redis with uid value" do
          redis.setnx(test_key, uid)
          adapter.has_key?(test_key).should be(true)
        end

        it "should return false if the key doesn't exist in redis or is a different uid" do
          redis.setnx(test_key, "notvalid")
          adapter.has_key?(test_key).should be(false)
          redis.del(test_key)
          adapter.has_key?(test_key).should be(false)
        end
      end

      describe "#delete" do
        it "should remove the key from redis" do
          redis.setnx(test_key, uid)
          adapter.delete(test_key)
          redis.get(test_key).should be_nil
        end
      end

      describe '#queue_key' do
        it 'returns the joined queue key' do
          expect(adapter.queue_key('key')).to eq 'key|queue'
        end
      end
    end
  end
end

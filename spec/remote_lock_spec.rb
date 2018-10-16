require 'spec_helper'

describe RemoteLock do

  adapters = {
    :redis => RemoteLock::Adapters::Redis.new(redis)
  }

  adapters.each_pair do |name, adapter|
    context "Using adapter: #{name}" do
      before do
        Kernel.stub(:sleep)
      end

      let(:lock) { RemoteLock.new(adapter) }

      describe "#synchronize" do

        it "yields the block" do
          expect { |call|
            lock.synchronize('lock_key', &call)
          }.to yield_control
        end

        it "acquires the specified lock before the block is run" do
          adapter.has_key?("lock_key").should be(false)
          lock.synchronize('lock_key') do
            adapter.has_key?("lock|lock_key").should be(true)
          end
        end

        it "releases the lock after the block is run" do
          adapter.has_key?("lock_key").should be(false)
          expect { |call| lock.synchronize('lock_key', &call) }.to yield_control
          adapter.has_key?("lock|lock_key").should be(false)
        end

        it "releases the lock even if the block raises" do
          adapter.has_key?("lock|lock_key").should be(false)
          lock.synchronize('lock_key') { raise } rescue nil
          adapter.has_key?("lock|lock_key").should be(false)
        end

        specify "does not block on recursive lock acquisition" do
          lock.synchronize('lock_key') do
            lambda {
              expect{ |call| lock.synchronize('lock_key', &call) }.to yield_control
            }.should_not raise_error
          end
        end

        it "permits recursive calls from the same thread" do
          lock.acquire_lock('lock_key')
          lambda {
            expect { |call| lock.synchronize('lock_key', &call) }.to yield_control
          }.should_not raise_error
        end

        it "prevents calls from different threads" do
          lock.acquire_lock('lock_key')
          another_thread do
            lambda {
              expect { |call| lock.synchronize('lock_key', retries: 1, &call) }.to_not yield_control
            }.should raise_error(RemoteLock::Error)
          end
        end
      end

      describe '#acquire_lock' do
        specify "creates a lock at a given cache key" do
          adapter.has_key?("lock|lock_key").should be(false)
          lock.acquire_lock("lock_key")
          adapter.has_key?("lock|lock_key").should be(true)
        end

        specify "retries specified number of times" do
          lock.acquire_lock('lock_key')
          another_process do
            adapter.should_receive(:store).exactly(2).times.and_return(false)
            lambda {
              lock.acquire_lock('lock_key', :expiry => 10, :retries => 1)
            }.should raise_error(RemoteLock::Error)
          end
        end

        specify "correctly sets timeout on entries" do
          adapter.should_receive(:store).with('lock|lock_key', 42).and_return true
          lock.acquire_lock('lock_key', :expiry => 42)
        end

        specify "prevents two processes from acquiring the same lock at the same time" do
          lock.acquire_lock('lock_key')
          another_process do
            lambda { lock.acquire_lock('lock_key', retries: 1) }.should raise_error(RemoteLock::Error)
          end
        end

        specify "prevents two threads from acquiring the same lock at the same time" do
          lock.acquire_lock('lock_key')
          another_thread do
            lambda { lock.acquire_lock('lock_key', retries: 1) }.should raise_error(RemoteLock::Error)
          end
        end

        specify "prevents a given thread from acquiring the same lock twice" do
          lock.acquire_lock('lock_key')
          lambda { lock.acquire_lock('lock_key', retries: 1) }.should raise_error(RemoteLock::Error)
        end

        it "grants locks in the order they were requested" do
          output = []

          another_thread do
            lock.synchronize('lock_key') do
              output << 1
              sleep 1
            end
          end

          another_thread do
            lock.synchronize('lock_key') do
              output << 3
            end
          end

          another_thread do
            lock.synchronize('lock_key') do
               output << 2
            end
          end

          expect(output).to eq [1,3,2]
        end

        it 'cleans up processes who were queued up but got disconnected' do
          output = []

          pid1 = Process.fork do
            redis.client.reconnect
            lock.synchronize('lock_key') do
              redis.sadd(:output, 1)
              sleep 1
            end
          end

          pid2 = Process.fork do
            redis.client.reconnect
            lambda do
              lock.synchronize('lock_key', retries: 1) do
                redis.sadd(:output, 3)
              end
            end.should raise_error(RemoteLock::Error)
          end

          sleep 0.1

          pid3 = Process.fork do
            redis.client.reconnect
            lock.synchronize('lock_key', initial_wait: 1, retries: 3) do
              redis.sadd(:output, 2)
            end
          end

          Process.wait(pid1)
          Process.wait(pid2)
          Process.wait(pid3)

          expect(redis.smembers(:output)).to match_array(["1", "2"])
        end
      end

      describe '#release_lock' do
        specify "deletes the lock for a given cache key" do
          adapter.has_key?("lock|lock_key").should be(false)
          lock.acquire_lock("lock_key")
          adapter.has_key?("lock|lock_key").should be(true)
          lock.release_lock("lock_key")
          adapter.has_key?("lock|lock_key").should be(false)
        end
      end

      context "lock prefixing" do
        it "should prefix the key name when a prefix is set" do
          lock = RemoteLock.new(adapter, "staging_server")
          lock.acquire_lock("lock_key")
          adapter.has_key?("staging_server|lock|lock_key").should be(true)
        end
      end
    end
  end

  #  helpers

  def another_process
    current_pid = Process.pid
    Process.stub :pid => (current_pid + 1)
    redis.client.reconnect
    yield
    Process.unstub :pid
    redis.client.reconnect
  end

  def another_thread
    old_tid = Thread.current[:thread_uid]
    Thread.current[:thread_uid] = nil
    yield
    Thread.current[:thread_uid] = old_tid
  end

end

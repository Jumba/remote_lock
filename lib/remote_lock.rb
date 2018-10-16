class RemoteLock
  class Error < RuntimeError; end

  DEFAULT_OPTIONS = {
    :initial_wait   => 10e-3, # seconds -- first soft fail will wait for 10ms
    :expiry         => 60,    # seconds
    :retries        => 11,    # these defaults will retry for a total 41sec max
  }

  def initialize(adapter, prefix = nil)
    raise "Invalid Adapter" unless Adapters::Base.valid?(adapter)
    @adapter = adapter
    @prefix = prefix
  end

  def synchronize(key, options={})
    if acquired?(key)
      yield
    else
      acquire_lock(key, options)
      begin
        yield
      ensure
        release_lock(key)
      end
    end
  end

  def acquire_lock(key, options = {})
    options = DEFAULT_OPTIONS.merge(options)
    lock_key = key_for(key)

    # Case 1: We immediately get the lock
    return if @adapter.store(lock_key, options[:expiry])

    # Case 2: Enter the queue
    @adapter.queue(lock_key)

    1.upto(options[:retries]) do |attempt|
      # Step 1: Renew queue membership
      @adapter.renew_queue

      if @adapter.next_in_queue?(lock_key)
        # Try to get a lock if it's your turn
        success = @adapter.store(lock_key, options[:expiry])
        if success
          @adapter.dequeue(lock_key)
          return
        end
      else
        # Trigger the cleanup logic
        @adapter.check_queue_membership(lock_key)
      end

      break if attempt == options[:retries]
      sleep(options[:initial_wait] + rand)
    end

    raise RemoteLock::Error, "Couldn't acquire lock for: #{key}"
  end

  def release_lock(key)
    @adapter.delete(key_for(key))
    @adapter.dequeue(key_for(key))
  end

  def acquired?(key)
    @adapter.has_key?(key_for(key))
  end

  private

  def key_for(string)
    [@prefix, "lock", string].compact.join('|')
  end

end

require 'remote_lock/adapters/redis'

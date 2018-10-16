require 'remote_lock/adapters/base'

module RemoteLock::Adapters
  class Redis < Base

    def store(key, expires_in_seconds)
      # The previous implementation used SETNX and EXPIRE in sequence to set the
      # lock. in case a previous client failed between SETNX and EXPIRE below,
      # the key may not expire.
      # We wrap setting the value and its expiry timestamp in a transaction.
      #
      # Caveat emptor: Redis transactions are *very* different from SQL
      # transactions.

      # cancel the next transaction if another client touches our key past
      # this point
      @connection.watch(key)

      # check if another client has the key.
      # it's important to still run a transaction to clear the watch.
      have_competition = @connection.exists(key)

      !! @connection.multi do
        break if have_competition
        @connection.setex(key, expires_in_seconds, uid)
      end
    end

    def delete(key)
      @connection.del(key)
    end

    def has_key?(key)
      @connection.get(key) == uid
    end

    def next_in_queue?(key)
      next_in_queue(key) == uid
    end

    def next_in_queue(key)
      @connection.lrange(queue_key(key), 0, 0).first
    end

    def queue(key)
      @connection.multi do
        @connection.rpush(queue_key(key), uid)
        @connection.setex(uid, 1, true)
      end
    end

    def renew_queue
      @connection.setex(uid, 1, true)
    end

    def check_queue_membership(key)
      target_uid = next_in_queue(key)

      return if target_uid.nil?

      unless @connection.get(target_uid)
        dequeue(key, target_uid: target_uid)
      end
    end

    def dequeue(key, target_uid: uid)
      @connection.multi do
        @connection.lrem(queue_key(key), 0, target_uid)
        @connection.del(target_uid)
      end
    end

    def queue_key(key)
      "#{key}_queue"
    end

  end
end

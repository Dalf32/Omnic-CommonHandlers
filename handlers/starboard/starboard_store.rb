# starboard_store.rb
#
# AUTHOR::  Kyle Mullins

require 'redis-objects'

class StarboardStore
  def initialize(server_redis)
    @redis = server_redis
    @excluded_channels_set = Redis::Set.new([@redis.namespace, :excluded_channels])
    @messages_hash = Redis::HashKey.new([@redis.namespace, :messages])
  end

  def enabled?
    @redis.exists?(:channel)
  end

  def disable
    @redis.del(:channel)
  end

  def channel
    @redis.get(:channel)
  end

  def channel=(channel_id)
    @redis.set(:channel, channel_id)
  end

  def threshold
    return 5 unless @redis.exists?(:threshold)

    @redis.get(:threshold).to_i
  end

  def threshold=(threshold)
    @redis.set(:threshold, threshold)
  end

  def emoji
    return '⭐' unless @redis.exists?(:emoji)

    # Pulling unicode emoji out of redis is a challenge...
    @redis.get(:emoji).encode('utf-8-hfs', 'utf-8').force_encoding('utf-8')
  end

  def emoji=(emoji)
    @redis.set(:emoji, emoji)
  end

  def excluded_channels
    @excluded_channels_set.members
  end

  def excluded?(channel_id)
    @excluded_channels_set.include?(channel_id)
  end

  def exclude_channel(channel_id)
    @excluded_channels_set.add(channel_id)
  end

  def include_channel(channel_id)
    @excluded_channels_set.delete(channel_id)
  end

  def on_board?(orig_msg_id)
    @messages_hash.key?(orig_msg_id)
  end

  def message(orig_msg_id)
    @messages_hash[orig_msg_id]
  end

  def add_message(orig_msg_id, starboard_msg_id)
    @messages_hash[orig_msg_id] = starboard_msg_id
  end

  def remove_message(orig_msg_id)
    @messages_hash.delete(orig_msg_id)
  end
end

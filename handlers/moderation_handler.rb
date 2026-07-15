# ModerationHandler.rb
#
# AUTHOR:: Kyle Mullins

class ModerationHandler < CommandHandler
  feature :moderation, default_enabled: false,
          description: 'Various moderation tools for larger servers.'

  command(:sethoneypot, :set_honeypot_channel)
    .feature(:moderation).args_range(0, 1).pm_enabled(false)
    .permissions(:moderate_members, :manage_channels)
    .usage('sethoneypot [channel]')
    .description('Sets a channel to be treated as a honeypot (ban anyone that messages there), or disables it if channel is omitted.')

  event(:message, :on_message).feature(:moderation).pm_enabled(false)

  def redis_name
    :moderation
  end

  def set_honeypot_channel(_event, *channel)
    if channel.empty?
      server_redis.del(HONEYPOT_KEY)
      return 'Honeypot disabled.'
    end

    found_channel = find_channel(channel.first)
    return found_channel.error if found_channel.failure?

    channel = found_channel.value
    channel.send("# DO NOT SEND MESSAGES IN THIS CHANNEL!\nYou will be immediately banned. This is not a joke.")
    server_redis.set(HONEYPOT_KEY, channel.id)

    "Honeypot channel set to #{channel.mention}."
  end

  def on_message(event)
    honeypot = honeypot_channel
    return if honeypot.nil?
    return unless event.message.channel.id == honeypot.id

    victim = event.message.author
    return if victim.bot_account?

    event.message.delete
    victim.ban(reason: 'Honeypot')
  rescue Discordrb::Errors::NoPermission
    log.warn("Bot lacks the permissions necessary to ban user: #{format_obj(victim)} in server: #{format_obj(server)}")
  end

  private

  HONEYPOT_KEY = :honeypot unless defined? HONEYPOT_KEY

  def honeypot_channel
    honeypot = server_redis.get(HONEYPOT_KEY)
    return nil if honeypot.nil? || honeypot.to_i.zero?

    bot.channel(honeypot.to_i, server)
  end
end

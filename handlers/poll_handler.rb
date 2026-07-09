# frozen_string_literal: true

class PollHandler < CommandHandler
  feature :polling, default_enabled: true,
          description: 'Allows running of polls with anonymous voting.'

  command(:poll, :create_poll)
    .feature(:polling).max_args(1).pm_enabled(false)
    .permissions(:manage_channels).usage('poll [channel]')
    .description('Creates a new poll and posts it to either the current or provided channel.')

  command(:pollresults, :check_results)
    .feature(:polling).max_args(1).pm_enabled(false)
    .usage('pollresults [channel]')
    .description('Posts results for the running or last poll to the current or provided channel.')

  command(:closepoll, :close_poll)
    .feature(:polling).no_args.pm_enabled(false).usage('closepoll')
    .description('Closes the running poll and saves the results.')

  command(:vote, :vote_in_poll)
    .feature(:polling).min_args(1).pm_enabled(false).usage('vote [option]...')
    .description("Enters the user's vote into the currently-running poll and deletes their message.")

  def redis_name
    :polling
  end

  def create_poll(event, *channel_name)
    # could also take title, auto-close time, max votes/user, etc.
    return 'Poll already active.' if poll_active?

    channel = event.message.channel
    unless channel_name.empty?
      channel_result = find_channel(channel_name.first)
      return 'Invalid channel.' if channel_result.failure?

      channel = channel_result.value
    end

    options = []
    opt_letter = 'A'

    loop do
      opt = prompt(event.message, "Enter option ##{options.count + 1} (#{opt_letter}) or END:")
      break if opt.nil? || opt == 'END'

      options << [opt_letter, opt]
      opt_letter = opt_letter.succ
    end

    return 'No options provided.' if options.empty?

    server_redis.set(ACTIVE_POLL_KEY, JSON.generate(options))

    formatted_options = options.map { |letter, option| "**#{letter}** - #{option}" }
    channel.send_message(formatted_options.join("\n"))
  end

  def check_results(event, *channel_name)
    channel = event.message.channel
    unless channel_name.empty?
      channel_result = find_channel(channel_name.first)
      return 'Invalid channel.' if channel_result.failure?

      channel = channel_result.value
    end

    opts, votes = poll_results
    return 'No active or past polls.' if opts.nil? || votes.nil?

    preamble = poll_active? ? 'Poll results so far' : 'Results from the last poll'
    channel.send_message("#{preamble}:\n#{format_poll_results(opts, votes)}")
  end

  def close_poll(_event)
    # we would want to keep the last run poll's results just in case
    return 'No active poll.' unless poll_active?

    server_redis.rename(ACTIVE_POLL_KEY, LAST_POLL_KEY)
    server_redis.rename(ACTIVE_VOTES_KEY, LAST_VOTES_KEY)
    "Poll closed!"
  end

  def vote_in_poll(event, *votes)
    return 'No active poll.' unless poll_active?

    opts = poll_options(ACTIVE_POLL_KEY)
    option_letters = opts.map(&:first)

    # check if user has votes left, etc.
    return "One or more votes were invalid." if votes.any? { |vote| !option_letters.include?(vote.upcase) }

    votes.map(&:upcase).each do |vote|
      server_redis.sadd(ACTIVE_VOTES_KEY, JSON.generate([vote, user.distinct]))
    end

    event.message.delete
  end

  private

  ACTIVE_POLL_KEY = :active_poll unless defined? ACTIVE_POLL_KEY
  ACTIVE_VOTES_KEY = :active_votes unless defined? ACTIVE_VOTES_KEY
  LAST_POLL_KEY = :last_poll unless defined? LAST_POLL_KEY
  LAST_VOTES_KEY = :last_votes unless defined? LAST_VOTES_KEY

  def prompt(message, prompt_str)
    message.reply(prompt_str)
    @user.await!(timeout: 60)&.text
  end

  def poll_active?
    server_redis.exists?(ACTIVE_POLL_KEY)
  end

  def has_last_poll?
    server_redis.exists?(LAST_POLL_KEY)
  end

  def poll_options(poll_key)
    JSON.parse(server_redis.get(poll_key))
  end

  def poll_votes(votes_key)
    server_redis.smembers(votes_key).map { |v| JSON.parse(v) }
  end

  def poll_results
    poll_key = LAST_POLL_KEY
    votes_key = LAST_VOTES_KEY

    if poll_active?
      poll_key = ACTIVE_POLL_KEY
      votes_key = ACTIVE_VOTES_KEY
    elsif !has_last_poll?
      return [nil, nil]
    end

    [poll_options(poll_key), poll_votes(votes_key)]
  end

  def format_poll_results(opts, votes)
    vote_groups = votes.group_by(&:first).values.sort_by(&:count).reverse

    results = vote_groups.map { |vg| [vg.first.first, vg.count] }
    results += opts.reject { |o| results.map { |r| r.first }.include?(o.first) }.map { |o| [o.first, 0] }
    results.map { |letter, count| "**(#{count})** #{letter} - #{opts.to_h[letter]}" }.join("\n")
  end
end

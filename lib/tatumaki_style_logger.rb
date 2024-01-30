require_relative 'tatumaki_style_logger/version'

require 'active_support'
require 'active_support/logger'
require 'active_support/tagged_logging'
require 'active_support/core_ext/time'

class TatumakiStyleLogger
  class PlainFormatter
    TAG_WRAPPER = proc { |name| "[#{name}]" }.freeze
    ANSI_PATTERN = /\e\[\d{1,3}[mK]/

    attr_reader :wrap, :human_friendry

    alias hf human_friendry

    def initialize wrap: 80, human_friendry: true
      @wrap = wrap
      @human_friendry = human_friendry
    end

    def call(severity, time, progname, msg)
      plain  = remove_tags msg, current_tags
      prefix = "#{time.iso8601} #{rich_severity severity} #{rich_tags current_tags}"
      text   = "#{rich_message severity, plain}"

      if wrap and prefix.length > wrap
        "#{prefix}\n  ↳ #{text}\n"
      elsif hf
        padding = ' ' * (prefix.gsub ANSI_PATTERN, '').length
        "#{prefix}#{text.gsub("\n", "\n" + padding)}\n"
      else
        "#{prefix}#{text}\n"
      end
    end

    def rich_severity severity
      aligned = '%-5s' % severity
      colored(severity, aligned)
    end

    def rich_message severity, msg
      colored(severity, msg)
    end

    def color severity
      case severity.to_s
      when 'DEBUG' then "\e[32m"
      when 'INFO'  then "\e[36m"
      when 'WARN'  then "\e[33m"
      when 'ERROR' then "\e[31m"
      when 'FATAL' then "\e[31m\e[6m"
      else :white
      end
    end

    def colored severity, string
      color = color(severity)
      "#{color}#{string}\e[0m"
    end

    def remove_tags msg, tags
      return msg if tags.empty?

      tag_str = tags.map(&TAG_WRAPPER).join(' ')
      msg.gsub(
        tag_str,
        ''
      )[1..-1]
    end

    # 見やすい色の範囲
    COLOR_RANGE = 0x16..0xe7
    COLOR_RANGE_SIZE = COLOR_RANGE.size

    def rich_tags tags
      return '' if tags.empty?
      tags.map do |tag|
        ansi_color = (tag.to_s.sum % COLOR_RANGE_SIZE) + COLOR_RANGE.first
        "\e[38;5;#{ansi_color}m" + tag.to_s + "\e[0m"
      end.map(&TAG_WRAPPER).join(' ') + ' '
    end
  end

  delegate_missing_to :@logger

  def initialize io=STDOUT, level: :debug, multicast: [], wrap: false, format: :plain, human_friendry: true
    logger = ActiveSupport::Logger.new(io)
    logger.formatter = PlainFormatter.new(wrap: wrap, human_friendry: human_friendry)

    @logger = ActiveSupport::TaggedLogging.new(logger)
    @logger.level = level
  end
end

TSLogger = TatumakiStyleLogger

require_relative 'tatumaki_style_logger/version'

require 'active_support'
require 'active_support/logger'
require 'active_support/tagged_logging'
require 'active_support/core_ext/time'

class TatumakiStyleLogger
  class Ascii
    def self.left n
      "\e[#{n}D"
    end

    def self.right n
      "\e[#{n}C"
    end
  end

  class PlainFormatter
    TAG_WRAPPER = proc { |name| "[#{name}]" }.freeze
    ANSI_PATTERN = /\e\[\d{1,3}[mK]/

    # options
    attr_reader :wrap, :human_friendly, :no_timestamp, :include_date

    DEFAULT_OPTIONS = {
      wrap: 80,
      human_friendly: true,
      no_timestamp: false,
      include_date: true,
    }

    def initialize **options
      {**DEFAULT_OPTIONS, **extract_options(options)} => {wrap:, human_friendly:, no_timestamp:, include_date:}

      @wrap           = wrap
      @human_friendly = human_friendly
      @no_timestamp   = no_timestamp
      @include_date   = include_date
    end

    def extract_options options
      options.slice(:wrap, :human_friendly, :no_timestamp, :include_date)
    end

    def bleach str
      str.gsub ANSI_PATTERN, ''
    end

    # 画面消去・スクロール・改行系はサポート外
    # \r, \e[5D (move left), \e[5C (move right) などを含めた文字列の幅
    def ansi_width str
      i = 0
      count = 0
      while i < str.length
        c = str[i]
        if c == "\e" and str[i+1] == '[' and str[i..(i+6)] =~ /\e\[(\d+)([CD])/
          w = $1.length + 1 + 1
          n = $1.to_i
          d = $2
          case d
          when 'D'
            count = [0, count - n].max
          when 'C'
            count = count + n
          end
          i += w
        elsif c == "\e" and str[i+1] == '['
          skip = 6.times do |j|
            k = str[i + j + 1]
            if k == 'm' or k == 'K'
              break j + 1
            end
          end
          i += skip
        elsif c == "\r"
          count = 0
        elsif c == "\n"
          # do nothing
        else
          count += 1
        end
        i += 1
      end

      return count
    end

    def call(severity, time, progname, msg)
      plain  = remove_tags msg, current_tags
      iso_time = time.iso8601
      d = iso_time[0..10]   # 2000-01-01T
      t = iso_time[11..] # 00:00:00+09:00

      datetime = if no_timestamp
        ""
      elsif human_friendly
        # 読みやすい時刻
        if include_date
          "#{d}#{Ascii.left 1} #{t}#{Ascii.left 6}      #{Ascii.left 6} "
        else
          "#{d}#{Ascii.left 11}#{t}#{Ascii.left 6}      #{Ascii.left 6} "
        end
      else
        # ISO8601フォーマットのまま
        "#{d}#{t} "
      end
      prefix = "#{datetime}#{rich_severity severity} #{rich_tags current_tags}"
      text   = "#{rich_message severity, plain}"

      if wrap and prefix.length > wrap
        "#{prefix}\n  ↳ #{text}\n"
      elsif human_friendly
        # 折り返しにパディングを入れて読みやすく
        padding = ' ' * ansi_width(prefix)
        "#{prefix}#{text.gsub("\n", "\n" + padding)}\n"
      else
        # 折り返しされたテキストは左端から始まる
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

  DEFAULT_OPTIONS = {
    level: :debug,
    multicast: [],
    wrap: false,
    format: :plain,
    human_friendly: true,
    include_date: true,
    no_timestamp: false,
  }

  def initialize io=STDOUT, **options
    options = {**DEFAULT_OPTIONS, **options}

    logger = ActiveSupport::Logger.new(io)
    logger.formatter = PlainFormatter.new(**options)

    @logger = ActiveSupport::TaggedLogging.new(logger)
    @logger.level = level
  end
end

# frozen_string_literal: true

require 'fileutils'
require 'zlib'

module Opal
  module Cache
    class FileCache
      def initialize(dir: nil, max_size: nil)
        @dir = dir || self.class.find_dir
        # Store at most 32MB of cache - de facto this 32MB is larger,
        # as we don't account for inode size for instance. In fact, it's
        # about 50M. Also we run this check before anything runs, so things
        # may go up to 64M or even larger.
        @max_size = max_size || 32 * 1024 * 1024

        tidy_up_cache
      end

      def set(key, data)
        file = cache_filename_for(key)

        out = Marshal.dump(data)
        out = Zlib.gzip(out, level: 9)
        File.binwrite(file, out)
      end

      def get(key)
        file = cache_filename_for(key)

        if File.exist?(file)
          FileUtils.touch(file)
          out = File.binread(file)
          out = Zlib.gunzip(out)
          Marshal.load(out) # rubocop:disable Security/MarshalLoad
        end
      rescue Zlib::GzipFile::Error
        nil
      end

      # Remove cache entries that overflow our cache limit... and which
      # were used least recently.
      private def tidy_up_cache
        entries = Dir[@dir + '/*.rbm.gz']

        size_sum = entries.map { |i| File.size(i) }.sum
        return unless size_sum > @max_size

        # First, we try to get the oldest files first.
        # Then, what's more important, is that we try to get the least
        # recently used files first. Filesystems with relatime or noatime
        # will get this wrong, but it doesn't matter that much, because
        # the previous sort got things "maybe right".
        entries = entries.sort_by { |i| [File.mtime(i), File.atime(i)] }

        entries.each do |i|
          size_sum -= File.size(i)
          File.unlink(i)

          # We don't need to work this out anymore - we reached out goal.
          break unless size_sum > @max_size
        end
      end

      # This complex piece of code tries to check if we can robustly mkdir_p a directory.
      def self.dir_writable?(*paths)
        dir = nil
        paths = paths.reduce([]) do |a, b|
          [*a, dir = a.last ? File.expand_path(b, a.last) : b]
        end

        File.exist?(paths.first) &&
          paths.reverse.all? do |i|
            !File.exist?(i) || (File.directory?(i) && File.writable?(i))
          end

        dir
      end

      def self.find_dir
        @find_dir ||= case
                      # Try to write cache into a directory pointed by an environment variable if present
                      when dir = ENV['OPAL_CACHE_DIR']
                        FileUtils.mkdir_p(dir)
                        dir
                      # Otherwise, we write to the place where Opal is installed...
                      # I don't think it's a good location to store cache, so many things can go wrong.
                      # when dir = dir_writable?(Opal.gem_dir, '..', 'tmp', 'cache')
                      #   FileUtils.mkdir_p(dir)
                      #   FileUtils.chmod(0o700, dir)
                      #   dir
                      # Otherwise, ~/.cache/opal...
                      when dir = dir_writable?(Dir.home, '.cache', 'opal')
                        FileUtils.mkdir_p(dir)
                        FileUtils.chmod(0o700, dir)
                        dir
                      # Only /tmp is writable... or isn't it?
                      when (dir = dir_writable?('/tmp', "opal-cache-#{ENV['USER']}")) && File.sticky?('/tmp')
                        FileUtils.mkdir_p(dir)
                        FileUtils.chmod(0o700, dir)
                        dir
                      # No way... we can't write anywhere...
                      else
                        warn "Couldn't find a writable path to store Opal cache. " \
                             'Try setting OPAL_CACHE_DIR environment variable'
                        nil
                      end
      end

      private def cache_filename_for(key)
        "#{@dir}/#{key}.rbm.gz"
      end
    end
  end
end
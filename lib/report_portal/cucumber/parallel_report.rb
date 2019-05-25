# Copyright 2015 EPAM Systems
# 
# 
# This file is part of Report Portal.
# 
# Report Portal is free software: you can redistribute it and/or modify
# it under the terms of the GNU Lesser General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# 
# ReportPortal is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Lesser General Public License for more details.
# 
# You should have received a copy of the GNU Lesser General Public License
# along with Report Portal.  If not, see <http://www.gnu.org/licenses/>.

require 'parallel_tests'
require 'sys/proctable'
require 'fileutils'

require_relative 'report'

module ReportPortal
  module Cucumber
    class ParallelReport < Report

      def parallel?
        true
      end

      def initialize(desired_time)
        @root_node = Tree::TreeNode.new('')
        ReportPortal.last_used_time = 0
        set_parallel_tests_vars
        if ParallelTests.first_process?
          start_launch(desired_time)
        else
          start_time = monotonic_time
          loop do
            break if File.exist?(lock_file)
            if monotonic_time - start_time > wait_time_for_launch_start
              raise "File with launch ID wasn't created after waiting #{wait_time_for_launch_start} seconds"
            end
            sleep 0.5
          end
          File.open(lock_file, 'r') do |f|
            ReportPortal.launch_id = f.read
          end
          add_process_description
          sleep_time = 5
          sleep(sleep_time) # stagger start times for reporting to Report Portal to avoid collision
        end
      end
      
      def add_process_description
        description = ReportPortal.get_launch['description'].split(' ')
        description.push(self.description().split(' '))
        ReportPortal.update_launch({description: description.join(' ')})
      end

      def done(desired_time = ReportPortal.now)
        end_feature(desired_time) if @feature_node

        if ParallelTests.first_process?
          ParallelTests.wait_for_other_processes_to_finish

          File.delete(lock_file)

          unless attach_to_launch?
            $stdout.puts "Finishing launch #{ReportPortal.launch_id}"
            ReportPortal.close_child_items(nil)
            time_to_send = time_to_send(desired_time)
            ReportPortal.finish_launch(time_to_send)
          end
        end
      end

      def lock_file
        file_path ||= tmp_dir + "parallel_launch_id_for_#{@pid_of_parallel_tests}.lock"
        file_path ||= ReportPortal::Settings.instance.file_with_launch_id
        file_path ||= tmp_dir + "report_portal_#{ReportPortal::Settings.instance.launch_uuid}.lock" if ReportPortal::Settings.instance.launch_uuid
        file_path ||= tmp_dir + 'rp_launch_id.tmp'
        file_path
      end
      
      private

      def set_parallel_tests_vars
        pid = Process.pid
        loop do
          current_process = Sys::ProcTable.ps(pid)
          #TODO: add exception to fall back to cucumber process 
          # 1. if rm_launch_uuid was created by some other parallel script that executes cucumber batch of feature files
          # 2. if fallback to cucumber process, this allows to use same formatter sequential and parallel executions
          # useful when formatters are default configured in AfterConfiguration hook 
          # config.formats.push(["ReportPortal::Cucumber::ParallelFormatter", {}, set_up_output_format(report_name, :report_portal)])
          raise 'Could not find parallel_cucumber/parallel_test in ancestors of current process' if current_process.nil?
          match = current_process.cmdline.match(/bin(?:\/|\\)parallel_(?:cucumber|test)(.+)/)
          if match
            @pid_of_parallel_tests = current_process.pid
            @cmd_args_of_parallel_tests = match[1].strip.split
            break
          end
          pid = Sys::ProcTable.ps(pid).ppid
        end
      end

      #time required for first tread to created remote project in RP and save id to file
      def wait_time_for_launch_start
        ENV['rp_parallel_launch_wait_time'] ? ENV['rp_parallel_launch_wait_time'] : 60
      end

      def monotonic_time
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end

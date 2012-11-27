# -*- coding: utf-8 -*-
#
# Copyright (C) 2011-2012  Kouhei Sutou <kou@clear-code.com>
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; either
# version 2.1 of the License, or (at your option) any later version.
#
# This library is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# License along with this library; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA

require "groonga/command"

module Groonga
  module QueryLog
    class Statistic
      attr_reader :context_id, :start_time, :raw_command
      attr_reader :elapsed, :return_code
      attr_accessor :slow_operation_threshold, :slow_response_threshold
      def initialize(context_id)
        @context_id = context_id
        @start_time = nil
        @command = nil
        @raw_command = nil
        @operations = []
        @elapsed = nil
        @return_code = 0
        @slow_operation_threshold = 0.1
        @slow_response_threshold = 0.2
      end

      def start(start_time, command)
        @start_time = start_time
        @raw_command = command
      end

      def finish(elapsed, return_code)
        @elapsed = elapsed
        @return_code = return_code
      end

      def command
        @command ||= Groonga::Command::Parser.parse(@raw_command)
      end

      def elapsed_in_seconds
        nano_seconds_to_seconds(@elapsed)
      end

      def last_time
        @start_time + elapsed_in_seconds
      end

      def slow?
        elapsed_in_seconds >= @slow_response_threshold
      end

      def each_operation
        previous_elapsed = 0
        ensure_parse_command
        operation_context_context = {
          :filter_index => 0,
          :drilldown_index => 0,
        }
        @operations.each_with_index do |operation, i|
          relative_elapsed = operation[:elapsed] - previous_elapsed
          relative_elapsed_in_seconds = nano_seconds_to_seconds(relative_elapsed)
          previous_elapsed = operation[:elapsed]
          parsed_operation = {
            :i => i,
            :elapsed => operation[:elapsed],
            :elapsed_in_seconds => nano_seconds_to_seconds(operation[:elapsed]),
            :relative_elapsed => relative_elapsed,
            :relative_elapsed_in_seconds => relative_elapsed_in_seconds,
            :name => operation[:name],
            :context => operation_context(operation[:name],
                                          operation_context_context),
            :n_records => operation[:n_records],
            :slow? => slow_operation?(relative_elapsed_in_seconds),
          }
          yield parsed_operation
        end
      end

      def add_operation(operation)
        @operations << operation
      end

      def operations
        _operations = []
        each_operation do |operation|
          _operations << operation
        end
        _operations
      end

      def select_command?
        command.name == "select"
      end

      private
      def nano_seconds_to_seconds(nano_seconds)
        nano_seconds / 1000.0 / 1000.0 / 1000.0
      end

      def operation_context(label, context)
        case label
        when "filter"
          if @select_command.query and context[:query_used].nil?
            context[:query_used] = true
            "query: #{@select_command.query}"
          else
            index = context[:filter_index]
            context[:filter_index] += 1
            @select_command.conditions[index]
          end
        when "sort"
          @select_command.sortby
        when "score"
          @select_command.scorer
        when "output"
          @select_command.output_columns
        when "drilldown"
          index = context[:drilldown_index]
          context[:drilldown_index] += 1
          @select_command.drilldowns[index]
        else
          nil
        end
      end

      def ensure_parse_command
        return unless select_command?
        @select_command = Groonga::Command::Parser.parse(@raw_command)
      end

      def slow_operation?(elapsed)
        elapsed >= @slow_operation_threshold
      end
    end
  end
end

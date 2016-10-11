################################################################################
# Copyright 2015 Marcelo Gornstein <marcelog@gmail.com>
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
################################################################################
defmodule LoggerLogstashBackendTest do
  use ExUnit.Case, async: false
  require Logger

  @backend {LoggerLogstashBackend, :test}
  Logger.add_backend @backend

  setup do
    Logger.configure(utc_log: true)
    Logger.configure_backend @backend, [
      host: "127.0.0.1",
      port: 10001,
      level: :info,
      type: "some_app",
      root_fields: [
        token: "abcd1234",
        tags: ["test"]
      ],
      metadata: [
        some_metadata: "go here"
      ]
    ]
    {:ok, socket} = :gen_udp.open 10001, [:binary, {:active, true}]
    on_exit fn ->
      :ok = :gen_udp.close socket
    end
    file_name = __ENV__.file
    {:ok, %{file_name: file_name}}
  end

  test "can log", %{file_name: file_name} do
    Logger.info "hello world", [key1: "field1"]
    log_line = __ENV__.line - 1
    pid = (inspect self)
    json = get_log
    {:ok, data} = JSX.decode json
    assert data["type"] === "some_app"
    assert data["message"] === "hello world"
    expected =  %{
      "function" => "test can log/1",
      "level" => "info",
      "module" => "Elixir.LoggerLogstashBackendTest",
      "pid" => pid,
      "some_metadata" => "go here",
      "line" => log_line,
      "file" => file_name,
      "key1" => "field1"
    }
    assert expected == data["metadata"]
  end

  test "can log pids", %{file_name: file_name} do
    Logger.info "pid", [pid_key: self]
    log_line = __ENV__.line - 1
    pid = (inspect self)
    json = get_log
    {:ok, data} = JSX.decode json
    assert data["type"] === "some_app"
    assert data["message"] === "pid"
    expected = %{
      "function" => "test can log pids/1",
      "level" => "info",
      "module" => "Elixir.LoggerLogstashBackendTest",
      "pid" => pid,
      "pid_key" => pid,
      "some_metadata" => "go here",
      "line" => log_line,
      "file" => file_name
    }
    assert expected == data["metadata"]
  end

  test "log timestamp" do
    Logger.info "logging timestamp"
    json = get_log
    {:ok, data} = JSX.decode json
    {:ok, timestamp} = NaiveDateTime.from_iso8601(data["@timestamp"])
    assert (DateTime.utc_now() |> DateTime.to_naive |> to_string) > (timestamp |> to_string)
  end

  test "log version" do
    Logger.info "log contain @version"
    json = get_log
    {:ok, data} = JSX.decode json
    assert data["@version"] === 1
  end

  test "log root fields" do
    Logger.info "log root fields"
    json = get_log
    {:ok, data} = JSX.decode json
    assert data["token"] === "abcd1234"
    assert data["tags"] === ["test"]
  end

  test "discard log when minor levels" do
    Logger.debug "hello world", [key1: "field1"]
    :nothing_received = get_log
  end

  defp get_log do
    receive do
      {:udp, _, _, _, json} -> json
    after 500 -> :nothing_received
    end
  end
end

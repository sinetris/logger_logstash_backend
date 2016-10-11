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
defmodule LoggerLogstashBackend do
  use GenEvent

  def init({__MODULE__, name}) do
    {:ok, configure(name, [])}
  end

  def handle_call({:configure, opts}, %{name: name}) do
    {:ok, :ok, configure(name, opts)}
  end

  def handle_event(:flush, state) do
    {:ok, state}
  end

  def handle_event(
    {level, _gl, {Logger, msg, ts, md}}, %{level: min_level} = state
  ) do
    if is_nil(min_level) or Logger.compare_levels(level, min_level) != :lt do
      log_event level, msg, ts, md, state
    end
    {:ok, state}
  end

  defp log_event(
    level, msg, ts, md, %{
      host: host,
      port: port,
      type: type,
      version: version,
      metadata: metadata,
      root_fields: root_fields,
      socket: socket
    }
  ) do
    fields = md
             |> Keyword.merge(metadata)
             |> Enum.into(%{})
             |> Map.put(:level, to_string(level))
             |> inspect_pids

    data =
      root_fields
      |> Enum.into(%{})
      |> Map.merge(%{
        type: type,
        "@timestamp": logger_datetime_to_iso8601(ts),
        "@version": version,
        message: to_string(msg),
        metadata: fields
      })
    {:ok, json} = JSX.encode(data)
    :gen_udp.send socket, host, port, json
  end

  defp configure(name, opts) do
    env = Application.get_env :logger, name, []
    opts = Keyword.merge env, opts
    Application.put_env :logger, name, opts

    level = Keyword.get opts, :level, :debug
    metadata = Keyword.get opts, :metadata, []
    type = Keyword.get opts, :type, "elixir"
    version = Keyword.get opts, :version, 1
    host = Keyword.get opts, :host
    port = Keyword.get(opts, :port) |> to_port()
    root_fields = Keyword.get opts, :root_fields, []
    {:ok, socket} = :gen_udp.open 0
    %{
      name: name,
      host: to_char_list(host),
      port: port,
      level: level,
      socket: socket,
      type: type,
      version: version,
      root_fields: root_fields,
      metadata: metadata
    }
  end

  # inspects the argument only if it is a pid
  defp inspect_pid(pid) when is_pid(pid), do: inspect(pid)
  defp inspect_pid(other), do: other

  # inspects the field values only if they are pids
  defp inspect_pids(fields) when is_map(fields) do
    Enum.into fields, %{}, fn {key, value} ->
      {key, inspect_pid(value)}
    end
  end

  defp logger_datetime_to_iso8601({{year, month, day}, {hour, minute, second, milliseconds}}) do
    {:ok, timestamp} = NaiveDateTime.new(
      year, month, day, hour, minute, second, (milliseconds * 1000)
    )
    timestamp
    |> NaiveDateTime.to_iso8601()
  end

  defp to_port(binary)  when is_binary(binary), do: String.to_integer(binary)
  defp to_port(integer) when is_integer(integer), do: integer
  defp to_port({:system, env_var}), do: to_port(System.get_env(env_var))
end

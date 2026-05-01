import Config

alias IRCane.BanMask
alias IRCane.Utils

config :ircane,
  channel_modes: %{
    ?b => {:param_always, :ban, list: true, parse: &BanMask.parse/1, format: &BanMask.format/1},
    # ?e => {:param_always, :exception, list: true, parse: &BanMask.parse/1, format: &BanMask.format/1}, # non-standard
    ?l =>
      {:param_when_set, :channel_limit,
       parse: &Utils.parse_integer/1, format: &Integer.to_string/1},
    ?i => {:no_param, :invite_only, []},
    # ?I => {:param_always, :invite_exception, list: true, parse: &BanMask.parse/1, format: &BanMask.format/1}, # non-standard
    ?k => {:param_always, :key, []},
    ?m => {:no_param, :moderated, []},
    ?s => {:no_param, :secret, []},
    ?t => {:no_param, :protected_topic, []},
    ?n => {:no_param, :no_external_messages, []},
    # ?q => {:param_always, :founder, []}, # non-standard
    # ?a => {:param_always, :protected, []}, # non-standard
    ?o => {:param_always, :operator, []},
    # ?h => {:param_always, :halfop, []}, # non-standard
    ?v => {:param_always, :voice, []}
  }

config :ircane,
  user_modes: %{
    ?i => {:no_param, :invisible, []},
    ?o => {:no_param, :local_operator, []},
    ?O => {:no_param, :global_operator, []},
    # ?r => {:no_param, :registered, []}, # non-standard
    ?w => {:no_param, :wallops, []}
  }

config :ircane,
  roles: [
    {:voice,
     %{
       prefix: ?+
     }},
    {:halfop,
     %{
       prefix: ?%,
       highest_target: :voice
     }},
    {:operator,
     %{
       prefix: ?@
     }},
    {:protect,
     %{
       prefix: ?&,
       highest_target: :operator
     }},
    {:founder,
     %{
       prefix: ?~,
       highest_target: :protect
     }}
  ]

config :ircane,
  listeners: [
    {ThousandIsland, handler_module: IRCane.Transport.TCP, port: 6667, read_timeout: :infinity}
  ],
  max_buffer_size: 8192,
  max_line: 510,
  event_dedup_size: 1000,
  network_name: "TestNet",
  server_name: "localhost",
  version: "ircane-0.1",
  registration_timeout_msec: 60_000,
  ping_timeout_msec: 120_000,
  heartbeat_interval_msec: 15_000

env_config = Path.join(__DIR__, "#{config_env()}.exs")

if File.exists?(env_config) do
  import_config "#{config_env()}.exs"
end

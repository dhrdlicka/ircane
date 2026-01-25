import Config

config :ircane,
  channel_modes: %{
    ?b => {:type_a, :ban},
    # ?e => {:type_a, :exception}, # non-standard
    ?l => {:type_c, :channel_limit},
    ?i => {:type_d, :invite_only},
    # ?I => {:type_a, :invite_exception}, # non-standard
    ?k => {:type_b, :key},
    ?m => {:type_d, :moderated},
    ?s => {:type_d, :secret},
    ?t => {:type_d, :protected_topic},
    ?n => {:type_d, :no_external_messages},
    # ?q => {:type_b, :founder}, # non-standard
    # ?a => {:type_b, :protected}, # non-standard
    ?o => {:type_b, :operator},
    # ?h => {:type_b, :halfop}, # non-standard
    ?v => {:type_b, :voice}
  }

config :ircane,
  user_modes: %{
    ?i => {:type_d, :invisible},
    ?o => {:type_d, :local_operator},
    ?O => {:type_d, :global_operator},
    # ?r => {:type_d, :registered}, # non-standard
    ?w => {:type_d, :wallops}
  }

config :ircane,
  mode_opts: %{
    channel_limit: [
      parse: &Utils.parse_integer/1,
      format: &Integer.to_string/1
    ],
    ban: [
      parse: &BanMask.parse/1,
      format: &BanMask.format/1
    ],
  }

config :ircane, prefixes: [voice: ?+, operator: ?@]

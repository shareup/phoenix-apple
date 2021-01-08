use Mix.Config

config :server, ServerWeb.Endpoint,
  http: [port: 4003],
  url: [host: "localhost"],
  secret_key_base: "x951AKdZkB9fM7C7DCuUc/DuoaLXULjSeFrI3Wrin6znJqB3J7nv9XelIKvgNAhC",
  render_errors: [view: ServerWeb.ErrorView, accepts: ~w(json)],
  pubsub_server: Server.PubSub,
  debug_errors: true,
  code_reloader: true,
  check_origin: false,
  watchers: []

config :logger, :console, format: "[$level] $message\n", level: :debug

config :phoenix, :stacktrace_depth, 20

config :phoenix, :plug_init_mode, :runtime

config :phoenix, :json_library, Jason

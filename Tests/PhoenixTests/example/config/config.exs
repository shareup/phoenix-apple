use Mix.Config

config :example, ExampleWeb.Endpoint,
  http: [port: 4000],
  url: [host: "localhost"],
  secret_key_base: "x951AKdZkB9fM7C7DCuUc/DuoaLXULjSeFrI3Wrin6znJqB3J7nv9XelIKvgNAhC",
  render_errors: [view: ExampleWeb.ErrorView, accepts: ~w(json)],
  pubsub: [name: Example.PubSub, adapter: Phoenix.PubSub.PG2],
  debug_errors: true,
  code_reloader: true,
  check_origin: false,
  watchers: []

config :logger, :console, format: "[$level] $message\n"

config :phoenix, :stacktrace_depth, 20

config :phoenix, :plug_init_mode, :runtime

config :phoenix, :json_library, Jason

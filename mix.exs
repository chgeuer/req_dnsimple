defmodule ReqDnsimple.MixProject do
  use Mix.Project

  def project do
    [
      app: :req_dnsimple,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:req, "~> 0.5"},
      {:nimble_options, "~> 1.1"}
    ]
  end
end

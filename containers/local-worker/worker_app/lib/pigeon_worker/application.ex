defmodule PigeonWorker.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do
    children = [
      {PigeonWorker.Server, []},
      {PigeonWorker.ControlNodeClient, []}
    ]

    opts = [strategy: :one_for_one, name: PigeonWorker.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
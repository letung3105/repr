defmodule Repr.Repo do
  use Ecto.Repo,
    otp_app: :repr,
    adapter: Ecto.Adapters.Postgres
end

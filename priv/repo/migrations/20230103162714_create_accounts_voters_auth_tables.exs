defmodule Repr.Repo.Migrations.CreateAccountsVotersAuthTables do
  use Ecto.Migration

  def change do
    execute "CREATE EXTENSION IF NOT EXISTS citext", ""

    create table(:accounts_voters) do
      add :email, :citext, null: false
      add :hashed_password, :string, null: false
      add :confirmed_at, :naive_datetime
      timestamps()
    end

    create unique_index(:accounts_voters, [:email])

    create table(:accounts_voters_tokens) do
      add :voter_id, references(:accounts_voters, on_delete: :delete_all), null: false
      add :token, :binary, null: false
      add :context, :string, null: false
      add :sent_to, :string
      timestamps(updated_at: false)
    end

    create index(:accounts_voters_tokens, [:voter_id])
    create unique_index(:accounts_voters_tokens, [:context, :token])
  end
end

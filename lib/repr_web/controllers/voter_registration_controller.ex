defmodule ReprWeb.VoterRegistrationController do
  use ReprWeb, :controller

  alias Repr.Accounts
  alias Repr.Accounts.Voter
  alias ReprWeb.VoterAuth

  def new(conn, _params) do
    changeset = Accounts.change_voter_registration(%Voter{})
    render(conn, "new.html", changeset: changeset)
  end

  def create(conn, %{"voter" => voter_params}) do
    case Accounts.register_voter(voter_params) do
      {:ok, voter} ->
        {:ok, _} =
          Accounts.deliver_voter_confirmation_instructions(
            voter,
            &Routes.voter_confirmation_url(conn, :edit, &1)
          )

        conn
        |> put_flash(:info, "Voter created successfully.")
        |> VoterAuth.log_in_voter(voter)

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, "new.html", changeset: changeset)
    end
  end
end

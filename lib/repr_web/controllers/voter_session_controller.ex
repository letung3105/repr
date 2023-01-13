defmodule ReprWeb.VoterSessionController do
  use ReprWeb, :controller

  alias Repr.Accounts
  alias ReprWeb.VoterAuth

  def new(conn, _params) do
    render(conn, "new.html", error_message: nil)
  end

  def create(conn, %{"voter" => voter_params}) do
    %{"email" => email, "password" => password} = voter_params

    if voter = Accounts.get_voter_by_email_and_password(email, password) do
      VoterAuth.log_in_voter(conn, voter, voter_params)
    else
      # In order to prevent user enumeration attacks, don't disclose whether the email is registered.
      render(conn, "new.html", error_message: "Invalid email or password")
    end
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully.")
    |> VoterAuth.log_out_voter()
  end
end

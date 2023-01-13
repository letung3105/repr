defmodule ReprWeb.VoterConfirmationController do
  use ReprWeb, :controller

  alias Repr.Accounts

  def new(conn, _params) do
    render(conn, "new.html")
  end

  def create(conn, %{"voter" => %{"email" => email}}) do
    if voter = Accounts.get_voter_by_email(email) do
      Accounts.deliver_voter_confirmation_instructions(
        voter,
        &Routes.voter_confirmation_url(conn, :edit, &1)
      )
    end

    conn
    |> put_flash(
      :info,
      "If your email is in our system and it has not been confirmed yet, " <>
        "you will receive an email with instructions shortly."
    )
    |> redirect(to: "/")
  end

  def edit(conn, %{"token" => token}) do
    render(conn, "edit.html", token: token)
  end

  # Do not log in the voter after confirmation to avoid a
  # leaked token giving the voter access to the account.
  def update(conn, %{"token" => token}) do
    case Accounts.confirm_voter(token) do
      {:ok, _} ->
        conn
        |> put_flash(:info, "Voter confirmed successfully.")
        |> redirect(to: "/")

      :error ->
        # If there is a current voter and the account was already confirmed,
        # then odds are that the confirmation link was already visited, either
        # by some automation or by the voter themselves, so we redirect without
        # a warning message.
        case conn.assigns do
          %{current_voter: %{confirmed_at: confirmed_at}} when not is_nil(confirmed_at) ->
            redirect(conn, to: "/")

          %{} ->
            conn
            |> put_flash(:error, "Voter confirmation link is invalid or it has expired.")
            |> redirect(to: "/")
        end
    end
  end
end

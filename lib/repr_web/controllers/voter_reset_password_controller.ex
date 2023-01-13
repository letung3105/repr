defmodule ReprWeb.VoterResetPasswordController do
  use ReprWeb, :controller

  alias Repr.Accounts

  plug :get_voter_by_reset_password_token when action in [:edit, :update]

  def new(conn, _params) do
    render(conn, "new.html")
  end

  def create(conn, %{"voter" => %{"email" => email}}) do
    if voter = Accounts.get_voter_by_email(email) do
      Accounts.deliver_voter_reset_password_instructions(
        voter,
        &Routes.voter_reset_password_url(conn, :edit, &1)
      )
    end

    conn
    |> put_flash(
      :info,
      "If your email is in our system, you will receive instructions to reset your password shortly."
    )
    |> redirect(to: "/")
  end

  def edit(conn, _params) do
    render(conn, "edit.html", changeset: Accounts.change_voter_password(conn.assigns.voter))
  end

  # Do not log in the voter after reset password to avoid a
  # leaked token giving the voter access to the account.
  def update(conn, %{"voter" => voter_params}) do
    case Accounts.reset_voter_password(conn.assigns.voter, voter_params) do
      {:ok, _} ->
        conn
        |> put_flash(:info, "Password reset successfully.")
        |> redirect(to: Routes.voter_session_path(conn, :new))

      {:error, changeset} ->
        render(conn, "edit.html", changeset: changeset)
    end
  end

  defp get_voter_by_reset_password_token(conn, _opts) do
    %{"token" => token} = conn.params

    if voter = Accounts.get_voter_by_reset_password_token(token) do
      conn |> assign(:voter, voter) |> assign(:token, token)
    else
      conn
      |> put_flash(:error, "Reset password link is invalid or it has expired.")
      |> redirect(to: "/")
      |> halt()
    end
  end
end

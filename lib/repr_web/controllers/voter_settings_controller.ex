defmodule ReprWeb.VoterSettingsController do
  use ReprWeb, :controller

  alias Repr.Accounts
  alias ReprWeb.VoterAuth

  plug :assign_email_and_password_changesets

  def edit(conn, _params) do
    render(conn, "edit.html")
  end

  def update(conn, %{"action" => "update_email"} = params) do
    %{"current_password" => password, "voter" => voter_params} = params
    voter = conn.assigns.current_voter

    case Accounts.apply_voter_email(voter, password, voter_params) do
      {:ok, applied_voter} ->
        Accounts.deliver_update_email_instructions(
          applied_voter,
          voter.email,
          &Routes.voter_settings_url(conn, :confirm_email, &1)
        )

        conn
        |> put_flash(
          :info,
          "A link to confirm your email change has been sent to the new address."
        )
        |> redirect(to: Routes.voter_settings_path(conn, :edit))

      {:error, changeset} ->
        render(conn, "edit.html", email_changeset: changeset)
    end
  end

  def update(conn, %{"action" => "update_password"} = params) do
    %{"current_password" => password, "voter" => voter_params} = params
    voter = conn.assigns.current_voter

    case Accounts.update_voter_password(voter, password, voter_params) do
      {:ok, voter} ->
        conn
        |> put_flash(:info, "Password updated successfully.")
        |> put_session(:voter_return_to, Routes.voter_settings_path(conn, :edit))
        |> VoterAuth.log_in_voter(voter)

      {:error, changeset} ->
        render(conn, "edit.html", password_changeset: changeset)
    end
  end

  def confirm_email(conn, %{"token" => token}) do
    case Accounts.update_voter_email(conn.assigns.current_voter, token) do
      :ok ->
        conn
        |> put_flash(:info, "Email changed successfully.")
        |> redirect(to: Routes.voter_settings_path(conn, :edit))

      :error ->
        conn
        |> put_flash(:error, "Email change link is invalid or it has expired.")
        |> redirect(to: Routes.voter_settings_path(conn, :edit))
    end
  end

  defp assign_email_and_password_changesets(conn, _opts) do
    voter = conn.assigns.current_voter

    conn
    |> assign(:email_changeset, Accounts.change_voter_email(voter))
    |> assign(:password_changeset, Accounts.change_voter_password(voter))
  end
end

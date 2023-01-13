defmodule ReprWeb.VoterSettingsControllerTest do
  use ReprWeb.ConnCase, async: true

  alias Repr.Accounts
  import Repr.AccountsFixtures

  setup :register_and_log_in_voter

  describe "GET /voters/settings" do
    test "renders settings page", %{conn: conn} do
      conn = get(conn, Routes.voter_settings_path(conn, :edit))
      response = html_response(conn, 200)
      assert response =~ "<h1>Settings</h1>"
    end

    test "redirects if voter is not logged in" do
      conn = build_conn()
      conn = get(conn, Routes.voter_settings_path(conn, :edit))
      assert redirected_to(conn) == Routes.voter_session_path(conn, :new)
    end
  end

  describe "PUT /voters/settings (change password form)" do
    test "updates the voter password and resets tokens", %{conn: conn, voter: voter} do
      new_password_conn =
        put(conn, Routes.voter_settings_path(conn, :update), %{
          "action" => "update_password",
          "current_password" => valid_voter_password(),
          "voter" => %{
            "password" => "new valid password",
            "password_confirmation" => "new valid password"
          }
        })

      assert redirected_to(new_password_conn) == Routes.voter_settings_path(conn, :edit)
      assert get_session(new_password_conn, :voter_token) != get_session(conn, :voter_token)
      assert get_flash(new_password_conn, :info) =~ "Password updated successfully"
      assert Accounts.get_voter_by_email_and_password(voter.email, "new valid password")
    end

    test "does not update password on invalid data", %{conn: conn} do
      old_password_conn =
        put(conn, Routes.voter_settings_path(conn, :update), %{
          "action" => "update_password",
          "current_password" => "invalid",
          "voter" => %{
            "password" => "too short",
            "password_confirmation" => "does not match"
          }
        })

      response = html_response(old_password_conn, 200)
      assert response =~ "<h1>Settings</h1>"
      assert response =~ "should be at least 12 character(s)"
      assert response =~ "does not match password"
      assert response =~ "is not valid"

      assert get_session(old_password_conn, :voter_token) == get_session(conn, :voter_token)
    end
  end

  describe "PUT /voters/settings (change email form)" do
    @tag :capture_log
    test "updates the voter email", %{conn: conn, voter: voter} do
      conn =
        put(conn, Routes.voter_settings_path(conn, :update), %{
          "action" => "update_email",
          "current_password" => valid_voter_password(),
          "voter" => %{"email" => unique_voter_email()}
        })

      assert redirected_to(conn) == Routes.voter_settings_path(conn, :edit)
      assert get_flash(conn, :info) =~ "A link to confirm your email"
      assert Accounts.get_voter_by_email(voter.email)
    end

    test "does not update email on invalid data", %{conn: conn} do
      conn =
        put(conn, Routes.voter_settings_path(conn, :update), %{
          "action" => "update_email",
          "current_password" => "invalid",
          "voter" => %{"email" => "with spaces"}
        })

      response = html_response(conn, 200)
      assert response =~ "<h1>Settings</h1>"
      assert response =~ "must have the @ sign and no spaces"
      assert response =~ "is not valid"
    end
  end

  describe "GET /voters/settings/confirm_email/:token" do
    setup %{voter: voter} do
      email = unique_voter_email()

      token =
        extract_voter_token(fn url ->
          Accounts.deliver_update_email_instructions(%{voter | email: email}, voter.email, url)
        end)

      %{token: token, email: email}
    end

    test "updates the voter email once", %{conn: conn, voter: voter, token: token, email: email} do
      conn = get(conn, Routes.voter_settings_path(conn, :confirm_email, token))
      assert redirected_to(conn) == Routes.voter_settings_path(conn, :edit)
      assert get_flash(conn, :info) =~ "Email changed successfully"
      refute Accounts.get_voter_by_email(voter.email)
      assert Accounts.get_voter_by_email(email)

      conn = get(conn, Routes.voter_settings_path(conn, :confirm_email, token))
      assert redirected_to(conn) == Routes.voter_settings_path(conn, :edit)
      assert get_flash(conn, :error) =~ "Email change link is invalid or it has expired"
    end

    test "does not update email with invalid token", %{conn: conn, voter: voter} do
      conn = get(conn, Routes.voter_settings_path(conn, :confirm_email, "oops"))
      assert redirected_to(conn) == Routes.voter_settings_path(conn, :edit)
      assert get_flash(conn, :error) =~ "Email change link is invalid or it has expired"
      assert Accounts.get_voter_by_email(voter.email)
    end

    test "redirects if voter is not logged in", %{token: token} do
      conn = build_conn()
      conn = get(conn, Routes.voter_settings_path(conn, :confirm_email, token))
      assert redirected_to(conn) == Routes.voter_session_path(conn, :new)
    end
  end
end

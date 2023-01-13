defmodule ReprWeb.VoterResetPasswordControllerTest do
  use ReprWeb.ConnCase, async: true

  alias Repr.Accounts
  alias Repr.Repo
  import Repr.AccountsFixtures

  setup do
    %{voter: voter_fixture()}
  end

  describe "GET /voters/reset_password" do
    test "renders the reset password page", %{conn: conn} do
      conn = get(conn, Routes.voter_reset_password_path(conn, :new))
      response = html_response(conn, 200)
      assert response =~ "<h1>Forgot your password?</h1>"
    end
  end

  describe "POST /voters/reset_password" do
    @tag :capture_log
    test "sends a new reset password token", %{conn: conn, voter: voter} do
      conn =
        post(conn, Routes.voter_reset_password_path(conn, :create), %{
          "voter" => %{"email" => voter.email}
        })

      assert redirected_to(conn) == "/"
      assert get_flash(conn, :info) =~ "If your email is in our system"
      assert Repo.get_by!(Accounts.VoterToken, voter_id: voter.id).context == "reset_password"
    end

    test "does not send reset password token if email is invalid", %{conn: conn} do
      conn =
        post(conn, Routes.voter_reset_password_path(conn, :create), %{
          "voter" => %{"email" => "unknown@example.com"}
        })

      assert redirected_to(conn) == "/"
      assert get_flash(conn, :info) =~ "If your email is in our system"
      assert Repo.all(Accounts.VoterToken) == []
    end
  end

  describe "GET /voters/reset_password/:token" do
    setup %{voter: voter} do
      token =
        extract_voter_token(fn url ->
          Accounts.deliver_voter_reset_password_instructions(voter, url)
        end)

      %{token: token}
    end

    test "renders reset password", %{conn: conn, token: token} do
      conn = get(conn, Routes.voter_reset_password_path(conn, :edit, token))
      assert html_response(conn, 200) =~ "<h1>Reset password</h1>"
    end

    test "does not render reset password with invalid token", %{conn: conn} do
      conn = get(conn, Routes.voter_reset_password_path(conn, :edit, "oops"))
      assert redirected_to(conn) == "/"
      assert get_flash(conn, :error) =~ "Reset password link is invalid or it has expired"
    end
  end

  describe "PUT /voters/reset_password/:token" do
    setup %{voter: voter} do
      token =
        extract_voter_token(fn url ->
          Accounts.deliver_voter_reset_password_instructions(voter, url)
        end)

      %{token: token}
    end

    test "resets password once", %{conn: conn, voter: voter, token: token} do
      conn =
        put(conn, Routes.voter_reset_password_path(conn, :update, token), %{
          "voter" => %{
            "password" => "new valid password",
            "password_confirmation" => "new valid password"
          }
        })

      assert redirected_to(conn) == Routes.voter_session_path(conn, :new)
      refute get_session(conn, :voter_token)
      assert get_flash(conn, :info) =~ "Password reset successfully"
      assert Accounts.get_voter_by_email_and_password(voter.email, "new valid password")
    end

    test "does not reset password on invalid data", %{conn: conn, token: token} do
      conn =
        put(conn, Routes.voter_reset_password_path(conn, :update, token), %{
          "voter" => %{
            "password" => "too short",
            "password_confirmation" => "does not match"
          }
        })

      response = html_response(conn, 200)
      assert response =~ "<h1>Reset password</h1>"
      assert response =~ "should be at least 12 character(s)"
      assert response =~ "does not match password"
    end

    test "does not reset password with invalid token", %{conn: conn} do
      conn = put(conn, Routes.voter_reset_password_path(conn, :update, "oops"))
      assert redirected_to(conn) == "/"
      assert get_flash(conn, :error) =~ "Reset password link is invalid or it has expired"
    end
  end
end

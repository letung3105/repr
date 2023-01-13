defmodule ReprWeb.VoterSessionControllerTest do
  use ReprWeb.ConnCase, async: true

  import Repr.AccountsFixtures

  setup do
    %{voter: voter_fixture()}
  end

  describe "GET /voters/log_in" do
    test "renders log in page", %{conn: conn} do
      conn = get(conn, Routes.voter_session_path(conn, :new))
      response = html_response(conn, 200)
      assert response =~ "<h1>Log in</h1>"
      assert response =~ "Register</a>"
      assert response =~ "Forgot your password?</a>"
    end

    test "redirects if already logged in", %{conn: conn, voter: voter} do
      conn = conn |> log_in_voter(voter) |> get(Routes.voter_session_path(conn, :new))
      assert redirected_to(conn) == "/"
    end
  end

  describe "POST /voters/log_in" do
    test "logs the voter in", %{conn: conn, voter: voter} do
      conn =
        post(conn, Routes.voter_session_path(conn, :create), %{
          "voter" => %{"email" => voter.email, "password" => valid_voter_password()}
        })

      assert get_session(conn, :voter_token)
      assert redirected_to(conn) == "/"

      # Now do a logged in request and assert on the menu
      conn = get(conn, "/")
      response = html_response(conn, 200)
      assert response =~ voter.email
      assert response =~ "Settings</a>"
      assert response =~ "Log out</a>"
    end

    test "logs the voter in with remember me", %{conn: conn, voter: voter} do
      conn =
        post(conn, Routes.voter_session_path(conn, :create), %{
          "voter" => %{
            "email" => voter.email,
            "password" => valid_voter_password(),
            "remember_me" => "true"
          }
        })

      assert conn.resp_cookies["_repr_web_voter_remember_me"]
      assert redirected_to(conn) == "/"
    end

    test "logs the voter in with return to", %{conn: conn, voter: voter} do
      conn =
        conn
        |> init_test_session(voter_return_to: "/foo/bar")
        |> post(Routes.voter_session_path(conn, :create), %{
          "voter" => %{
            "email" => voter.email,
            "password" => valid_voter_password()
          }
        })

      assert redirected_to(conn) == "/foo/bar"
    end

    test "emits error message with invalid credentials", %{conn: conn, voter: voter} do
      conn =
        post(conn, Routes.voter_session_path(conn, :create), %{
          "voter" => %{"email" => voter.email, "password" => "invalid_password"}
        })

      response = html_response(conn, 200)
      assert response =~ "<h1>Log in</h1>"
      assert response =~ "Invalid email or password"
    end
  end

  describe "DELETE /voters/log_out" do
    test "logs the voter out", %{conn: conn, voter: voter} do
      conn = conn |> log_in_voter(voter) |> delete(Routes.voter_session_path(conn, :delete))
      assert redirected_to(conn) == "/"
      refute get_session(conn, :voter_token)
      assert get_flash(conn, :info) =~ "Logged out successfully"
    end

    test "succeeds even if the voter is not logged in", %{conn: conn} do
      conn = delete(conn, Routes.voter_session_path(conn, :delete))
      assert redirected_to(conn) == "/"
      refute get_session(conn, :voter_token)
      assert get_flash(conn, :info) =~ "Logged out successfully"
    end
  end
end

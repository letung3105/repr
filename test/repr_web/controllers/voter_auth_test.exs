defmodule ReprWeb.VoterAuthTest do
  use ReprWeb.ConnCase, async: true

  alias Repr.Accounts
  alias ReprWeb.VoterAuth
  import Repr.AccountsFixtures

  @remember_me_cookie "_repr_web_voter_remember_me"

  setup %{conn: conn} do
    conn =
      conn
      |> Map.replace!(:secret_key_base, ReprWeb.Endpoint.config(:secret_key_base))
      |> init_test_session(%{})

    %{voter: voter_fixture(), conn: conn}
  end

  describe "log_in_voter/3" do
    test "stores the voter token in the session", %{conn: conn, voter: voter} do
      conn = VoterAuth.log_in_voter(conn, voter)
      assert token = get_session(conn, :voter_token)
      assert get_session(conn, :live_socket_id) == "voters_sessions:#{Base.url_encode64(token)}"
      assert redirected_to(conn) == "/"
      assert Accounts.get_voter_by_session_token(token)
    end

    test "clears everything previously stored in the session", %{conn: conn, voter: voter} do
      conn = conn |> put_session(:to_be_removed, "value") |> VoterAuth.log_in_voter(voter)
      refute get_session(conn, :to_be_removed)
    end

    test "redirects to the configured path", %{conn: conn, voter: voter} do
      conn = conn |> put_session(:voter_return_to, "/hello") |> VoterAuth.log_in_voter(voter)
      assert redirected_to(conn) == "/hello"
    end

    test "writes a cookie if remember_me is configured", %{conn: conn, voter: voter} do
      conn = conn |> fetch_cookies() |> VoterAuth.log_in_voter(voter, %{"remember_me" => "true"})
      assert get_session(conn, :voter_token) == conn.cookies[@remember_me_cookie]

      assert %{value: signed_token, max_age: max_age} = conn.resp_cookies[@remember_me_cookie]
      assert signed_token != get_session(conn, :voter_token)
      assert max_age == 5_184_000
    end
  end

  describe "logout_voter/1" do
    test "erases session and cookies", %{conn: conn, voter: voter} do
      voter_token = Accounts.generate_voter_session_token(voter)

      conn =
        conn
        |> put_session(:voter_token, voter_token)
        |> put_req_cookie(@remember_me_cookie, voter_token)
        |> fetch_cookies()
        |> VoterAuth.log_out_voter()

      refute get_session(conn, :voter_token)
      refute conn.cookies[@remember_me_cookie]
      assert %{max_age: 0} = conn.resp_cookies[@remember_me_cookie]
      assert redirected_to(conn) == "/"
      refute Accounts.get_voter_by_session_token(voter_token)
    end

    test "broadcasts to the given live_socket_id", %{conn: conn} do
      live_socket_id = "voters_sessions:abcdef-token"
      ReprWeb.Endpoint.subscribe(live_socket_id)

      conn
      |> put_session(:live_socket_id, live_socket_id)
      |> VoterAuth.log_out_voter()

      assert_receive %Phoenix.Socket.Broadcast{event: "disconnect", topic: ^live_socket_id}
    end

    test "works even if voter is already logged out", %{conn: conn} do
      conn = conn |> fetch_cookies() |> VoterAuth.log_out_voter()
      refute get_session(conn, :voter_token)
      assert %{max_age: 0} = conn.resp_cookies[@remember_me_cookie]
      assert redirected_to(conn) == "/"
    end
  end

  describe "fetch_current_voter/2" do
    test "authenticates voter from session", %{conn: conn, voter: voter} do
      voter_token = Accounts.generate_voter_session_token(voter)
      conn = conn |> put_session(:voter_token, voter_token) |> VoterAuth.fetch_current_voter([])
      assert conn.assigns.current_voter.id == voter.id
    end

    test "authenticates voter from cookies", %{conn: conn, voter: voter} do
      logged_in_conn =
        conn |> fetch_cookies() |> VoterAuth.log_in_voter(voter, %{"remember_me" => "true"})

      voter_token = logged_in_conn.cookies[@remember_me_cookie]
      %{value: signed_token} = logged_in_conn.resp_cookies[@remember_me_cookie]

      conn =
        conn
        |> put_req_cookie(@remember_me_cookie, signed_token)
        |> VoterAuth.fetch_current_voter([])

      assert get_session(conn, :voter_token) == voter_token
      assert conn.assigns.current_voter.id == voter.id
    end

    test "does not authenticate if data is missing", %{conn: conn, voter: voter} do
      _ = Accounts.generate_voter_session_token(voter)
      conn = VoterAuth.fetch_current_voter(conn, [])
      refute get_session(conn, :voter_token)
      refute conn.assigns.current_voter
    end
  end

  describe "redirect_if_voter_is_authenticated/2" do
    test "redirects if voter is authenticated", %{conn: conn, voter: voter} do
      conn = conn |> assign(:current_voter, voter) |> VoterAuth.redirect_if_voter_is_authenticated([])
      assert conn.halted
      assert redirected_to(conn) == "/"
    end

    test "does not redirect if voter is not authenticated", %{conn: conn} do
      conn = VoterAuth.redirect_if_voter_is_authenticated(conn, [])
      refute conn.halted
      refute conn.status
    end
  end

  describe "require_authenticated_voter/2" do
    test "redirects if voter is not authenticated", %{conn: conn} do
      conn = conn |> fetch_flash() |> VoterAuth.require_authenticated_voter([])
      assert conn.halted
      assert redirected_to(conn) == Routes.voter_session_path(conn, :new)
      assert get_flash(conn, :error) == "You must log in to access this page."
    end

    test "stores the path to redirect to on GET", %{conn: conn} do
      halted_conn =
        %{conn | path_info: ["foo"], query_string: ""}
        |> fetch_flash()
        |> VoterAuth.require_authenticated_voter([])

      assert halted_conn.halted
      assert get_session(halted_conn, :voter_return_to) == "/foo"

      halted_conn =
        %{conn | path_info: ["foo"], query_string: "bar=baz"}
        |> fetch_flash()
        |> VoterAuth.require_authenticated_voter([])

      assert halted_conn.halted
      assert get_session(halted_conn, :voter_return_to) == "/foo?bar=baz"

      halted_conn =
        %{conn | path_info: ["foo"], query_string: "bar", method: "POST"}
        |> fetch_flash()
        |> VoterAuth.require_authenticated_voter([])

      assert halted_conn.halted
      refute get_session(halted_conn, :voter_return_to)
    end

    test "does not redirect if voter is authenticated", %{conn: conn, voter: voter} do
      conn = conn |> assign(:current_voter, voter) |> VoterAuth.require_authenticated_voter([])
      refute conn.halted
      refute conn.status
    end
  end
end

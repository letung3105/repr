defmodule ReprWeb.VoterConfirmationControllerTest do
  use ReprWeb.ConnCase, async: true

  alias Repr.Accounts
  alias Repr.Repo
  import Repr.AccountsFixtures

  setup do
    %{voter: voter_fixture()}
  end

  describe "GET /voters/confirm" do
    test "renders the resend confirmation page", %{conn: conn} do
      conn = get(conn, Routes.voter_confirmation_path(conn, :new))
      response = html_response(conn, 200)
      assert response =~ "<h1>Resend confirmation instructions</h1>"
    end
  end

  describe "POST /voters/confirm" do
    @tag :capture_log
    test "sends a new confirmation token", %{conn: conn, voter: voter} do
      conn =
        post(conn, Routes.voter_confirmation_path(conn, :create), %{
          "voter" => %{"email" => voter.email}
        })

      assert redirected_to(conn) == "/"
      assert get_flash(conn, :info) =~ "If your email is in our system"
      assert Repo.get_by!(Accounts.VoterToken, voter_id: voter.id).context == "confirm"
    end

    test "does not send confirmation token if Voter is confirmed", %{conn: conn, voter: voter} do
      Repo.update!(Accounts.Voter.confirm_changeset(voter))

      conn =
        post(conn, Routes.voter_confirmation_path(conn, :create), %{
          "voter" => %{"email" => voter.email}
        })

      assert redirected_to(conn) == "/"
      assert get_flash(conn, :info) =~ "If your email is in our system"
      refute Repo.get_by(Accounts.VoterToken, voter_id: voter.id)
    end

    test "does not send confirmation token if email is invalid", %{conn: conn} do
      conn =
        post(conn, Routes.voter_confirmation_path(conn, :create), %{
          "voter" => %{"email" => "unknown@example.com"}
        })

      assert redirected_to(conn) == "/"
      assert get_flash(conn, :info) =~ "If your email is in our system"
      assert Repo.all(Accounts.VoterToken) == []
    end
  end

  describe "GET /voters/confirm/:token" do
    test "renders the confirmation page", %{conn: conn} do
      conn = get(conn, Routes.voter_confirmation_path(conn, :edit, "some-token"))
      response = html_response(conn, 200)
      assert response =~ "<h1>Confirm account</h1>"

      form_action = Routes.voter_confirmation_path(conn, :update, "some-token")
      assert response =~ "action=\"#{form_action}\""
    end
  end

  describe "POST /voters/confirm/:token" do
    test "confirms the given token once", %{conn: conn, voter: voter} do
      token =
        extract_voter_token(fn url ->
          Accounts.deliver_voter_confirmation_instructions(voter, url)
        end)

      conn = post(conn, Routes.voter_confirmation_path(conn, :update, token))
      assert redirected_to(conn) == "/"
      assert get_flash(conn, :info) =~ "Voter confirmed successfully"
      assert Accounts.get_voter!(voter.id).confirmed_at
      refute get_session(conn, :voter_token)
      assert Repo.all(Accounts.VoterToken) == []

      # When not logged in
      conn = post(conn, Routes.voter_confirmation_path(conn, :update, token))
      assert redirected_to(conn) == "/"
      assert get_flash(conn, :error) =~ "Voter confirmation link is invalid or it has expired"

      # When logged in
      conn =
        build_conn()
        |> log_in_voter(voter)
        |> post(Routes.voter_confirmation_path(conn, :update, token))

      assert redirected_to(conn) == "/"
      refute get_flash(conn, :error)
    end

    test "does not confirm email with invalid token", %{conn: conn, voter: voter} do
      conn = post(conn, Routes.voter_confirmation_path(conn, :update, "oops"))
      assert redirected_to(conn) == "/"
      assert get_flash(conn, :error) =~ "Voter confirmation link is invalid or it has expired"
      refute Accounts.get_voter!(voter.id).confirmed_at
    end
  end
end

defmodule ReprWeb.VoterAuth do
  import Plug.Conn
  import Phoenix.Controller

  alias Repr.Accounts
  alias ReprWeb.Router.Helpers, as: Routes

  # Make the remember me cookie valid for 60 days.
  # If you want bump or reduce this value, also change
  # the token expiry itself in VoterToken.
  @max_age 60 * 60 * 24 * 60
  @remember_me_cookie "_repr_web_voter_remember_me"
  @remember_me_options [sign: true, max_age: @max_age, same_site: "Lax"]

  @doc """
  Logs the voter in.

  It renews the session ID and clears the whole session
  to avoid fixation attacks. See the renew_session
  function to customize this behaviour.

  It also sets a `:live_socket_id` key in the session,
  so LiveView sessions are identified and automatically
  disconnected on log out. The line can be safely removed
  if you are not using LiveView.
  """
  def log_in_voter(conn, voter, params \\ %{}) do
    token = Accounts.generate_voter_session_token(voter)
    voter_return_to = get_session(conn, :voter_return_to)

    conn
    |> renew_session()
    |> put_session(:voter_token, token)
    |> put_session(:live_socket_id, "voters_sessions:#{Base.url_encode64(token)}")
    |> maybe_write_remember_me_cookie(token, params)
    |> redirect(to: voter_return_to || signed_in_path(conn))
  end

  defp maybe_write_remember_me_cookie(conn, token, %{"remember_me" => "true"}) do
    put_resp_cookie(conn, @remember_me_cookie, token, @remember_me_options)
  end

  defp maybe_write_remember_me_cookie(conn, _token, _params) do
    conn
  end

  # This function renews the session ID and erases the whole
  # session to avoid fixation attacks. If there is any data
  # in the session you may want to preserve after log in/log out,
  # you must explicitly fetch the session data before clearing
  # and then immediately set it after clearing, for example:
  #
  #     defp renew_session(conn) do
  #       preferred_locale = get_session(conn, :preferred_locale)
  #
  #       conn
  #       |> configure_session(renew: true)
  #       |> clear_session()
  #       |> put_session(:preferred_locale, preferred_locale)
  #     end
  #
  defp renew_session(conn) do
    conn
    |> configure_session(renew: true)
    |> clear_session()
  end

  @doc """
  Logs the voter out.

  It clears all session data for safety. See renew_session.
  """
  def log_out_voter(conn) do
    voter_token = get_session(conn, :voter_token)
    voter_token && Accounts.delete_session_token(voter_token)

    if live_socket_id = get_session(conn, :live_socket_id) do
      ReprWeb.Endpoint.broadcast(live_socket_id, "disconnect", %{})
    end

    conn
    |> renew_session()
    |> delete_resp_cookie(@remember_me_cookie)
    |> redirect(to: "/")
  end

  @doc """
  Authenticates the voter by looking into the session
  and remember me token.
  """
  def fetch_current_voter(conn, _opts) do
    {voter_token, conn} = ensure_voter_token(conn)
    voter = voter_token && Accounts.get_voter_by_session_token(voter_token)
    assign(conn, :current_voter, voter)
  end

  defp ensure_voter_token(conn) do
    if voter_token = get_session(conn, :voter_token) do
      {voter_token, conn}
    else
      conn = fetch_cookies(conn, signed: [@remember_me_cookie])

      if voter_token = conn.cookies[@remember_me_cookie] do
        {voter_token, put_session(conn, :voter_token, voter_token)}
      else
        {nil, conn}
      end
    end
  end

  @doc """
  Used for routes that require the voter to not be authenticated.
  """
  def redirect_if_voter_is_authenticated(conn, _opts) do
    if conn.assigns[:current_voter] do
      conn
      |> redirect(to: signed_in_path(conn))
      |> halt()
    else
      conn
    end
  end

  @doc """
  Used for routes that require the voter to be authenticated.

  If you want to enforce the voter email is confirmed before
  they use the application at all, here would be a good place.
  """
  def require_authenticated_voter(conn, _opts) do
    if conn.assigns[:current_voter] do
      conn
    else
      conn
      |> put_flash(:error, "You must log in to access this page.")
      |> maybe_store_return_to()
      |> redirect(to: Routes.voter_session_path(conn, :new))
      |> halt()
    end
  end

  defp maybe_store_return_to(%{method: "GET"} = conn) do
    put_session(conn, :voter_return_to, current_path(conn))
  end

  defp maybe_store_return_to(conn), do: conn

  defp signed_in_path(_conn), do: "/"
end

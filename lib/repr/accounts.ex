defmodule Repr.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false
  alias Repr.Repo

  alias Repr.Accounts.{Voter, VoterToken, VoterNotifier}

  ## Database getters

  @doc """
  Gets a voter by email.

  ## Examples

      iex> get_voter_by_email("foo@example.com")
      %Voter{}

      iex> get_voter_by_email("unknown@example.com")
      nil

  """
  def get_voter_by_email(email) when is_binary(email) do
    Repo.get_by(Voter, email: email)
  end

  @doc """
  Gets a voter by email and password.

  ## Examples

      iex> get_voter_by_email_and_password("foo@example.com", "correct_password")
      %Voter{}

      iex> get_voter_by_email_and_password("foo@example.com", "invalid_password")
      nil

  """
  def get_voter_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    voter = Repo.get_by(Voter, email: email)
    if Voter.valid_password?(voter, password), do: voter
  end

  @doc """
  Gets a single voter.

  Raises `Ecto.NoResultsError` if the Voter does not exist.

  ## Examples

      iex> get_voter!(123)
      %Voter{}

      iex> get_voter!(456)
      ** (Ecto.NoResultsError)

  """
  def get_voter!(id), do: Repo.get!(Voter, id)

  ## Voter registration

  @doc """
  Registers a voter.

  ## Examples

      iex> register_voter(%{field: value})
      {:ok, %Voter{}}

      iex> register_voter(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def register_voter(attrs) do
    %Voter{}
    |> Voter.registration_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking voter changes.

  ## Examples

      iex> change_voter_registration(voter)
      %Ecto.Changeset{data: %Voter{}}

  """
  def change_voter_registration(%Voter{} = voter, attrs \\ %{}) do
    Voter.registration_changeset(voter, attrs, hash_password: false)
  end

  ## Settings

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the voter email.

  ## Examples

      iex> change_voter_email(voter)
      %Ecto.Changeset{data: %Voter{}}

  """
  def change_voter_email(voter, attrs \\ %{}) do
    Voter.email_changeset(voter, attrs)
  end

  @doc """
  Emulates that the email will change without actually changing
  it in the database.

  ## Examples

      iex> apply_voter_email(voter, "valid password", %{email: ...})
      {:ok, %Voter{}}

      iex> apply_voter_email(voter, "invalid password", %{email: ...})
      {:error, %Ecto.Changeset{}}

  """
  def apply_voter_email(voter, password, attrs) do
    voter
    |> Voter.email_changeset(attrs)
    |> Voter.validate_current_password(password)
    |> Ecto.Changeset.apply_action(:update)
  end

  @doc """
  Updates the voter email using the given token.

  If the token matches, the voter email is updated and the token is deleted.
  The confirmed_at date is also updated to the current time.
  """
  def update_voter_email(voter, token) do
    context = "change:#{voter.email}"

    with {:ok, query} <- VoterToken.verify_change_email_token_query(token, context),
         %VoterToken{sent_to: email} <- Repo.one(query),
         {:ok, _} <- Repo.transaction(voter_email_multi(voter, email, context)) do
      :ok
    else
      _ -> :error
    end
  end

  defp voter_email_multi(voter, email, context) do
    changeset =
      voter
      |> Voter.email_changeset(%{email: email})
      |> Voter.confirm_changeset()

    Ecto.Multi.new()
    |> Ecto.Multi.update(:voter, changeset)
    |> Ecto.Multi.delete_all(:tokens, VoterToken.voter_and_contexts_query(voter, [context]))
  end

  @doc """
  Delivers the update email instructions to the given voter.

  ## Examples

      iex> deliver_update_email_instructions(voter, current_email, &Routes.voter_update_email_url(conn, :edit, &1))
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_update_email_instructions(%Voter{} = voter, current_email, update_email_url_fun)
      when is_function(update_email_url_fun, 1) do
    {encoded_token, voter_token} = VoterToken.build_email_token(voter, "change:#{current_email}")

    Repo.insert!(voter_token)
    VoterNotifier.deliver_update_email_instructions(voter, update_email_url_fun.(encoded_token))
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the voter password.

  ## Examples

      iex> change_voter_password(voter)
      %Ecto.Changeset{data: %Voter{}}

  """
  def change_voter_password(voter, attrs \\ %{}) do
    Voter.password_changeset(voter, attrs, hash_password: false)
  end

  @doc """
  Updates the voter password.

  ## Examples

      iex> update_voter_password(voter, "valid password", %{password: ...})
      {:ok, %Voter{}}

      iex> update_voter_password(voter, "invalid password", %{password: ...})
      {:error, %Ecto.Changeset{}}

  """
  def update_voter_password(voter, password, attrs) do
    changeset =
      voter
      |> Voter.password_changeset(attrs)
      |> Voter.validate_current_password(password)

    Ecto.Multi.new()
    |> Ecto.Multi.update(:voter, changeset)
    |> Ecto.Multi.delete_all(:tokens, VoterToken.voter_and_contexts_query(voter, :all))
    |> Repo.transaction()
    |> case do
      {:ok, %{voter: voter}} -> {:ok, voter}
      {:error, :voter, changeset, _} -> {:error, changeset}
    end
  end

  ## Session

  @doc """
  Generates a session token.
  """
  def generate_voter_session_token(voter) do
    {token, voter_token} = VoterToken.build_session_token(voter)
    Repo.insert!(voter_token)
    token
  end

  @doc """
  Gets the voter with the given signed token.
  """
  def get_voter_by_session_token(token) do
    {:ok, query} = VoterToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_session_token(token) do
    Repo.delete_all(VoterToken.token_and_context_query(token, "session"))
    :ok
  end

  ## Confirmation

  @doc """
  Delivers the confirmation email instructions to the given voter.

  ## Examples

      iex> deliver_voter_confirmation_instructions(voter, &Routes.voter_confirmation_url(conn, :edit, &1))
      {:ok, %{to: ..., body: ...}}

      iex> deliver_voter_confirmation_instructions(confirmed_voter, &Routes.voter_confirmation_url(conn, :edit, &1))
      {:error, :already_confirmed}

  """
  def deliver_voter_confirmation_instructions(%Voter{} = voter, confirmation_url_fun)
      when is_function(confirmation_url_fun, 1) do
    if voter.confirmed_at do
      {:error, :already_confirmed}
    else
      {encoded_token, voter_token} = VoterToken.build_email_token(voter, "confirm")
      Repo.insert!(voter_token)
      VoterNotifier.deliver_confirmation_instructions(voter, confirmation_url_fun.(encoded_token))
    end
  end

  @doc """
  Confirms a voter by the given token.

  If the token matches, the voter account is marked as confirmed
  and the token is deleted.
  """
  def confirm_voter(token) do
    with {:ok, query} <- VoterToken.verify_email_token_query(token, "confirm"),
         %Voter{} = voter <- Repo.one(query),
         {:ok, %{voter: voter}} <- Repo.transaction(confirm_voter_multi(voter)) do
      {:ok, voter}
    else
      _ -> :error
    end
  end

  defp confirm_voter_multi(voter) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:voter, Voter.confirm_changeset(voter))
    |> Ecto.Multi.delete_all(:tokens, VoterToken.voter_and_contexts_query(voter, ["confirm"]))
  end

  ## Reset password

  @doc """
  Delivers the reset password email to the given voter.

  ## Examples

      iex> deliver_voter_reset_password_instructions(voter, &Routes.voter_reset_password_url(conn, :edit, &1))
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_voter_reset_password_instructions(%Voter{} = voter, reset_password_url_fun)
      when is_function(reset_password_url_fun, 1) do
    {encoded_token, voter_token} = VoterToken.build_email_token(voter, "reset_password")
    Repo.insert!(voter_token)
    VoterNotifier.deliver_reset_password_instructions(voter, reset_password_url_fun.(encoded_token))
  end

  @doc """
  Gets the voter by reset password token.

  ## Examples

      iex> get_voter_by_reset_password_token("validtoken")
      %Voter{}

      iex> get_voter_by_reset_password_token("invalidtoken")
      nil

  """
  def get_voter_by_reset_password_token(token) do
    with {:ok, query} <- VoterToken.verify_email_token_query(token, "reset_password"),
         %Voter{} = voter <- Repo.one(query) do
      voter
    else
      _ -> nil
    end
  end

  @doc """
  Resets the voter password.

  ## Examples

      iex> reset_voter_password(voter, %{password: "new long password", password_confirmation: "new long password"})
      {:ok, %Voter{}}

      iex> reset_voter_password(voter, %{password: "valid", password_confirmation: "not the same"})
      {:error, %Ecto.Changeset{}}

  """
  def reset_voter_password(voter, attrs) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:voter, Voter.password_changeset(voter, attrs))
    |> Ecto.Multi.delete_all(:tokens, VoterToken.voter_and_contexts_query(voter, :all))
    |> Repo.transaction()
    |> case do
      {:ok, %{voter: voter}} -> {:ok, voter}
      {:error, :voter, changeset, _} -> {:error, changeset}
    end
  end
end

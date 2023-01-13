defmodule Repr.AccountsTest do
  use Repr.DataCase

  alias Repr.Accounts

  import Repr.AccountsFixtures
  alias Repr.Accounts.{Voter, VoterToken}

  describe "get_voter_by_email/1" do
    test "does not return the voter if the email does not exist" do
      refute Accounts.get_voter_by_email("unknown@example.com")
    end

    test "returns the voter if the email exists" do
      %{id: id} = voter = voter_fixture()
      assert %Voter{id: ^id} = Accounts.get_voter_by_email(voter.email)
    end
  end

  describe "get_voter_by_email_and_password/2" do
    test "does not return the voter if the email does not exist" do
      refute Accounts.get_voter_by_email_and_password("unknown@example.com", "hello world!")
    end

    test "does not return the voter if the password is not valid" do
      voter = voter_fixture()
      refute Accounts.get_voter_by_email_and_password(voter.email, "invalid")
    end

    test "returns the voter if the email and password are valid" do
      %{id: id} = voter = voter_fixture()

      assert %Voter{id: ^id} =
               Accounts.get_voter_by_email_and_password(voter.email, valid_voter_password())
    end
  end

  describe "get_voter!/1" do
    test "raises if id is invalid" do
      assert_raise Ecto.NoResultsError, fn ->
        Accounts.get_voter!(-1)
      end
    end

    test "returns the voter with the given id" do
      %{id: id} = voter = voter_fixture()
      assert %Voter{id: ^id} = Accounts.get_voter!(voter.id)
    end
  end

  describe "register_voter/1" do
    test "requires email and password to be set" do
      {:error, changeset} = Accounts.register_voter(%{})

      assert %{
               password: ["can't be blank"],
               email: ["can't be blank"]
             } = errors_on(changeset)
    end

    test "validates email and password when given" do
      {:error, changeset} = Accounts.register_voter(%{email: "not valid", password: "not valid"})

      assert %{
               email: ["must have the @ sign and no spaces"],
               password: ["should be at least 12 character(s)"]
             } = errors_on(changeset)
    end

    test "validates maximum values for email and password for security" do
      too_long = String.duplicate("db", 100)
      {:error, changeset} = Accounts.register_voter(%{email: too_long, password: too_long})
      assert "should be at most 160 character(s)" in errors_on(changeset).email
      assert "should be at most 72 character(s)" in errors_on(changeset).password
    end

    test "validates email uniqueness" do
      %{email: email} = voter_fixture()
      {:error, changeset} = Accounts.register_voter(%{email: email})
      assert "has already been taken" in errors_on(changeset).email

      # Now try with the upper cased email too, to check that email case is ignored.
      {:error, changeset} = Accounts.register_voter(%{email: String.upcase(email)})
      assert "has already been taken" in errors_on(changeset).email
    end

    test "registers voters with a hashed password" do
      email = unique_voter_email()
      {:ok, voter} = Accounts.register_voter(valid_voter_attributes(email: email))
      assert voter.email == email
      assert is_binary(voter.hashed_password)
      assert is_nil(voter.confirmed_at)
      assert is_nil(voter.password)
    end
  end

  describe "change_voter_registration/2" do
    test "returns a changeset" do
      assert %Ecto.Changeset{} = changeset = Accounts.change_voter_registration(%Voter{})
      assert changeset.required == [:password, :email]
    end

    test "allows fields to be set" do
      email = unique_voter_email()
      password = valid_voter_password()

      changeset =
        Accounts.change_voter_registration(
          %Voter{},
          valid_voter_attributes(email: email, password: password)
        )

      assert changeset.valid?
      assert get_change(changeset, :email) == email
      assert get_change(changeset, :password) == password
      assert is_nil(get_change(changeset, :hashed_password))
    end
  end

  describe "change_voter_email/2" do
    test "returns a voter changeset" do
      assert %Ecto.Changeset{} = changeset = Accounts.change_voter_email(%Voter{})
      assert changeset.required == [:email]
    end
  end

  describe "apply_voter_email/3" do
    setup do
      %{voter: voter_fixture()}
    end

    test "requires email to change", %{voter: voter} do
      {:error, changeset} = Accounts.apply_voter_email(voter, valid_voter_password(), %{})
      assert %{email: ["did not change"]} = errors_on(changeset)
    end

    test "validates email", %{voter: voter} do
      {:error, changeset} =
        Accounts.apply_voter_email(voter, valid_voter_password(), %{email: "not valid"})

      assert %{email: ["must have the @ sign and no spaces"]} = errors_on(changeset)
    end

    test "validates maximum value for email for security", %{voter: voter} do
      too_long = String.duplicate("db", 100)

      {:error, changeset} =
        Accounts.apply_voter_email(voter, valid_voter_password(), %{email: too_long})

      assert "should be at most 160 character(s)" in errors_on(changeset).email
    end

    test "validates email uniqueness", %{voter: voter} do
      %{email: email} = voter_fixture()

      {:error, changeset} =
        Accounts.apply_voter_email(voter, valid_voter_password(), %{email: email})

      assert "has already been taken" in errors_on(changeset).email
    end

    test "validates current password", %{voter: voter} do
      {:error, changeset} =
        Accounts.apply_voter_email(voter, "invalid", %{email: unique_voter_email()})

      assert %{current_password: ["is not valid"]} = errors_on(changeset)
    end

    test "applies the email without persisting it", %{voter: voter} do
      email = unique_voter_email()
      {:ok, voter} = Accounts.apply_voter_email(voter, valid_voter_password(), %{email: email})
      assert voter.email == email
      assert Accounts.get_voter!(voter.id).email != email
    end
  end

  describe "deliver_update_email_instructions/3" do
    setup do
      %{voter: voter_fixture()}
    end

    test "sends token through notification", %{voter: voter} do
      token =
        extract_voter_token(fn url ->
          Accounts.deliver_update_email_instructions(voter, "current@example.com", url)
        end)

      {:ok, token} = Base.url_decode64(token, padding: false)
      assert voter_token = Repo.get_by(VoterToken, token: :crypto.hash(:sha256, token))
      assert voter_token.voter_id == voter.id
      assert voter_token.sent_to == voter.email
      assert voter_token.context == "change:current@example.com"
    end
  end

  describe "update_voter_email/2" do
    setup do
      voter = voter_fixture()
      email = unique_voter_email()

      token =
        extract_voter_token(fn url ->
          Accounts.deliver_update_email_instructions(%{voter | email: email}, voter.email, url)
        end)

      %{voter: voter, token: token, email: email}
    end

    test "updates the email with a valid token", %{voter: voter, token: token, email: email} do
      assert Accounts.update_voter_email(voter, token) == :ok
      changed_voter = Repo.get!(Voter, voter.id)
      assert changed_voter.email != voter.email
      assert changed_voter.email == email
      assert changed_voter.confirmed_at
      assert changed_voter.confirmed_at != voter.confirmed_at
      refute Repo.get_by(VoterToken, voter_id: voter.id)
    end

    test "does not update email with invalid token", %{voter: voter} do
      assert Accounts.update_voter_email(voter, "oops") == :error
      assert Repo.get!(Voter, voter.id).email == voter.email
      assert Repo.get_by(VoterToken, voter_id: voter.id)
    end

    test "does not update email if voter email changed", %{voter: voter, token: token} do
      assert Accounts.update_voter_email(%{voter | email: "current@example.com"}, token) == :error
      assert Repo.get!(Voter, voter.id).email == voter.email
      assert Repo.get_by(VoterToken, voter_id: voter.id)
    end

    test "does not update email if token expired", %{voter: voter, token: token} do
      {1, nil} = Repo.update_all(VoterToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])
      assert Accounts.update_voter_email(voter, token) == :error
      assert Repo.get!(Voter, voter.id).email == voter.email
      assert Repo.get_by(VoterToken, voter_id: voter.id)
    end
  end

  describe "change_voter_password/2" do
    test "returns a voter changeset" do
      assert %Ecto.Changeset{} = changeset = Accounts.change_voter_password(%Voter{})
      assert changeset.required == [:password]
    end

    test "allows fields to be set" do
      changeset =
        Accounts.change_voter_password(%Voter{}, %{
          "password" => "new valid password"
        })

      assert changeset.valid?
      assert get_change(changeset, :password) == "new valid password"
      assert is_nil(get_change(changeset, :hashed_password))
    end
  end

  describe "update_voter_password/3" do
    setup do
      %{voter: voter_fixture()}
    end

    test "validates password", %{voter: voter} do
      {:error, changeset} =
        Accounts.update_voter_password(voter, valid_voter_password(), %{
          password: "not valid",
          password_confirmation: "another"
        })

      assert %{
               password: ["should be at least 12 character(s)"],
               password_confirmation: ["does not match password"]
             } = errors_on(changeset)
    end

    test "validates maximum values for password for security", %{voter: voter} do
      too_long = String.duplicate("db", 100)

      {:error, changeset} =
        Accounts.update_voter_password(voter, valid_voter_password(), %{password: too_long})

      assert "should be at most 72 character(s)" in errors_on(changeset).password
    end

    test "validates current password", %{voter: voter} do
      {:error, changeset} =
        Accounts.update_voter_password(voter, "invalid", %{password: valid_voter_password()})

      assert %{current_password: ["is not valid"]} = errors_on(changeset)
    end

    test "updates the password", %{voter: voter} do
      {:ok, voter} =
        Accounts.update_voter_password(voter, valid_voter_password(), %{
          password: "new valid password"
        })

      assert is_nil(voter.password)
      assert Accounts.get_voter_by_email_and_password(voter.email, "new valid password")
    end

    test "deletes all tokens for the given voter", %{voter: voter} do
      _ = Accounts.generate_voter_session_token(voter)

      {:ok, _} =
        Accounts.update_voter_password(voter, valid_voter_password(), %{
          password: "new valid password"
        })

      refute Repo.get_by(VoterToken, voter_id: voter.id)
    end
  end

  describe "generate_voter_session_token/1" do
    setup do
      %{voter: voter_fixture()}
    end

    test "generates a token", %{voter: voter} do
      token = Accounts.generate_voter_session_token(voter)
      assert voter_token = Repo.get_by(VoterToken, token: token)
      assert voter_token.context == "session"

      # Creating the same token for another voter should fail
      assert_raise Ecto.ConstraintError, fn ->
        Repo.insert!(%VoterToken{
          token: voter_token.token,
          voter_id: voter_fixture().id,
          context: "session"
        })
      end
    end
  end

  describe "get_voter_by_session_token/1" do
    setup do
      voter = voter_fixture()
      token = Accounts.generate_voter_session_token(voter)
      %{voter: voter, token: token}
    end

    test "returns voter by token", %{voter: voter, token: token} do
      assert session_voter = Accounts.get_voter_by_session_token(token)
      assert session_voter.id == voter.id
    end

    test "does not return voter for invalid token" do
      refute Accounts.get_voter_by_session_token("oops")
    end

    test "does not return voter for expired token", %{token: token} do
      {1, nil} = Repo.update_all(VoterToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])
      refute Accounts.get_voter_by_session_token(token)
    end
  end

  describe "delete_session_token/1" do
    test "deletes the token" do
      voter = voter_fixture()
      token = Accounts.generate_voter_session_token(voter)
      assert Accounts.delete_session_token(token) == :ok
      refute Accounts.get_voter_by_session_token(token)
    end
  end

  describe "deliver_voter_confirmation_instructions/2" do
    setup do
      %{voter: voter_fixture()}
    end

    test "sends token through notification", %{voter: voter} do
      token =
        extract_voter_token(fn url ->
          Accounts.deliver_voter_confirmation_instructions(voter, url)
        end)

      {:ok, token} = Base.url_decode64(token, padding: false)
      assert voter_token = Repo.get_by(VoterToken, token: :crypto.hash(:sha256, token))
      assert voter_token.voter_id == voter.id
      assert voter_token.sent_to == voter.email
      assert voter_token.context == "confirm"
    end
  end

  describe "confirm_voter/1" do
    setup do
      voter = voter_fixture()

      token =
        extract_voter_token(fn url ->
          Accounts.deliver_voter_confirmation_instructions(voter, url)
        end)

      %{voter: voter, token: token}
    end

    test "confirms the email with a valid token", %{voter: voter, token: token} do
      assert {:ok, confirmed_voter} = Accounts.confirm_voter(token)
      assert confirmed_voter.confirmed_at
      assert confirmed_voter.confirmed_at != voter.confirmed_at
      assert Repo.get!(Voter, voter.id).confirmed_at
      refute Repo.get_by(VoterToken, voter_id: voter.id)
    end

    test "does not confirm with invalid token", %{voter: voter} do
      assert Accounts.confirm_voter("oops") == :error
      refute Repo.get!(Voter, voter.id).confirmed_at
      assert Repo.get_by(VoterToken, voter_id: voter.id)
    end

    test "does not confirm email if token expired", %{voter: voter, token: token} do
      {1, nil} = Repo.update_all(VoterToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])
      assert Accounts.confirm_voter(token) == :error
      refute Repo.get!(Voter, voter.id).confirmed_at
      assert Repo.get_by(VoterToken, voter_id: voter.id)
    end
  end

  describe "deliver_voter_reset_password_instructions/2" do
    setup do
      %{voter: voter_fixture()}
    end

    test "sends token through notification", %{voter: voter} do
      token =
        extract_voter_token(fn url ->
          Accounts.deliver_voter_reset_password_instructions(voter, url)
        end)

      {:ok, token} = Base.url_decode64(token, padding: false)
      assert voter_token = Repo.get_by(VoterToken, token: :crypto.hash(:sha256, token))
      assert voter_token.voter_id == voter.id
      assert voter_token.sent_to == voter.email
      assert voter_token.context == "reset_password"
    end
  end

  describe "get_voter_by_reset_password_token/1" do
    setup do
      voter = voter_fixture()

      token =
        extract_voter_token(fn url ->
          Accounts.deliver_voter_reset_password_instructions(voter, url)
        end)

      %{voter: voter, token: token}
    end

    test "returns the voter with valid token", %{voter: %{id: id}, token: token} do
      assert %Voter{id: ^id} = Accounts.get_voter_by_reset_password_token(token)
      assert Repo.get_by(VoterToken, voter_id: id)
    end

    test "does not return the voter with invalid token", %{voter: voter} do
      refute Accounts.get_voter_by_reset_password_token("oops")
      assert Repo.get_by(VoterToken, voter_id: voter.id)
    end

    test "does not return the voter if token expired", %{voter: voter, token: token} do
      {1, nil} = Repo.update_all(VoterToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])
      refute Accounts.get_voter_by_reset_password_token(token)
      assert Repo.get_by(VoterToken, voter_id: voter.id)
    end
  end

  describe "reset_voter_password/2" do
    setup do
      %{voter: voter_fixture()}
    end

    test "validates password", %{voter: voter} do
      {:error, changeset} =
        Accounts.reset_voter_password(voter, %{
          password: "not valid",
          password_confirmation: "another"
        })

      assert %{
               password: ["should be at least 12 character(s)"],
               password_confirmation: ["does not match password"]
             } = errors_on(changeset)
    end

    test "validates maximum values for password for security", %{voter: voter} do
      too_long = String.duplicate("db", 100)
      {:error, changeset} = Accounts.reset_voter_password(voter, %{password: too_long})
      assert "should be at most 72 character(s)" in errors_on(changeset).password
    end

    test "updates the password", %{voter: voter} do
      {:ok, updated_voter} = Accounts.reset_voter_password(voter, %{password: "new valid password"})
      assert is_nil(updated_voter.password)
      assert Accounts.get_voter_by_email_and_password(voter.email, "new valid password")
    end

    test "deletes all tokens for the given voter", %{voter: voter} do
      _ = Accounts.generate_voter_session_token(voter)
      {:ok, _} = Accounts.reset_voter_password(voter, %{password: "new valid password"})
      refute Repo.get_by(VoterToken, voter_id: voter.id)
    end
  end

  describe "inspect/2" do
    test "does not include password" do
      refute inspect(%Voter{password: "123456"}) =~ "password: \"123456\""
    end
  end
end

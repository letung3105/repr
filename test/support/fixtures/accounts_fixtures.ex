defmodule Repr.AccountsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Repr.Accounts` context.
  """

  def unique_voter_email, do: "voter#{System.unique_integer()}@example.com"
  def valid_voter_password, do: "hello world!"

  def valid_voter_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      email: unique_voter_email(),
      password: valid_voter_password()
    })
  end

  def voter_fixture(attrs \\ %{}) do
    {:ok, voter} =
      attrs
      |> valid_voter_attributes()
      |> Repr.Accounts.register_voter()

    voter
  end

  def extract_voter_token(fun) do
    {:ok, captured_email} = fun.(&"[TOKEN]#{&1}[TOKEN]")
    [_, token | _] = String.split(captured_email.text_body, "[TOKEN]")
    token
  end
end

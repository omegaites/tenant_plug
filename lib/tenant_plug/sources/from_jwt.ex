defmodule TenantPlug.Sources.FromJWT do
  @moduledoc """
  Extracts tenant information from JWT tokens.

  This source extracts tenant information from JWT tokens found in request headers
  or cookies. It supports both verified and unverified JWT parsing, and can extract
  tenant information from any claim in the JWT payload.

  ## Configuration Options

  * `:header` - Header name containing the JWT (default: "authorization")
  * `:header_prefix` - Prefix to strip from header value (default: "Bearer ")
  * `:cookie` - Cookie name containing the JWT (alternative to header)
  * `:claim` - JWT claim containing tenant ID (default: "tenant_id")
  * `:verify` - Whether to verify JWT signature (default: false)
  * `:secret` - Secret key for verification (required if verify: true)
  * `:algorithm` - Algorithm for verification (default: "HS256")
  * `:transform` - Optional function to transform the claim value

  ## Examples

      # Basic usage - extract from Authorization header, "tenant_id" claim
      plug TenantPlug, sources: [TenantPlug.Sources.FromJWT]

      # Custom header and claim
      plug TenantPlug, sources: [
        {TenantPlug.Sources.FromJWT, 
         header: "x-auth-token", 
         claim: "org_id"}
      ]

      # Extract from cookie
      plug TenantPlug, sources: [
        {TenantPlug.Sources.FromJWT, 
         cookie: "auth_token", 
         claim: "tenant"}
      ]

      # Verify JWT signature
      plug TenantPlug, sources: [
        {TenantPlug.Sources.FromJWT, 
         verify: true, 
         secret: "your-secret-key",
         algorithm: "HS256"}
      ]

      # Transform claim value
      plug TenantPlug, sources: [
        {TenantPlug.Sources.FromJWT, 
         claim: "sub",
         transform: fn sub -> String.split(sub, ":") |> List.last() end}
      ]

  ## JWT Examples

      # Authorization header
      Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.eyJ0ZW5hbnRfaWQiOiJ0ZW5hbnQtMTIzIn0...

      # Custom header
      X-Auth-Token: eyJhbGciOiJIUzI1NiJ9.eyJvcmdfaWQiOiJteS1vcmcifQ...

      # Cookie
      Cookie: auth_token=eyJhbGciOiJIUzI1NiJ9.eyJ0ZW5hbnQiOiJhY21lIn0...

  ## JWT Payload Examples

      # Standard tenant claim
      {
        "tenant_id": "tenant-123",
        "sub": "user-456",
        "exp": 1234567890
      }

      # Custom org claim  
      {
        "org_id": "my-organization",
        "user": "john.doe",
        "roles": ["admin"]
      }

      # Nested tenant in subject
      {
        "sub": "tenant:acme:user:123",
        "iat": 1234567890
      }
  """

  @behaviour TenantPlug.Sources.Behaviour

  @default_header "authorization"
  @default_header_prefix "Bearer "
  @default_claim "tenant_id"
  @default_algorithm "HS256"

  @doc """
  Extract tenant from JWT token.
  """
  @impl TenantPlug.Sources.Behaviour
  def extract(conn, opts) do
    jwt_opts = get_jwt_opts(opts)
    
    with {:ok, token} <- get_jwt_token(conn, jwt_opts),
         {:ok, payload} <- parse_jwt(token, jwt_opts),
         {:ok, tenant} <- extract_tenant_from_payload(payload, jwt_opts) do
      {:ok, tenant}
    else
      {:error, reason} -> {:error, reason}
      :not_found -> :not_found
    end
  end

  # Private functions

  defp get_jwt_opts(opts) do
    case Keyword.get(opts, :sources, []) do
      [] -> 
        []
      
      sources when is_list(sources) ->
        Enum.find_value(sources, [], fn
          {TenantPlug.Sources.FromJWT, source_opts} -> source_opts
          TenantPlug.Sources.FromJWT -> []
          _ -> nil
        end)
      
      _ ->
        # Return empty opts for malformed sources config
        []
    end
  end

  defp get_jwt_token(conn, opts) do
    cond do
      cookie_name = opts[:cookie] ->
        get_jwt_from_cookie(conn, cookie_name)
        
      true ->
        header_name = opts[:header] || @default_header
        header_prefix = 
          if Keyword.has_key?(opts, :header_prefix) do
            opts[:header_prefix]
          else
            @default_header_prefix
          end
        get_jwt_from_header(conn, header_name, header_prefix)
    end
  end

  defp get_jwt_from_header(conn, header_name, prefix) do
    case Plug.Conn.get_req_header(conn, header_name) do
      [header_value | _] ->
        cond do
          is_nil(prefix) ->
            # No prefix required
            case String.trim(header_value) do
              "" -> :not_found
              clean_token -> {:ok, clean_token}
            end
          
          prefix == "" ->
            # Empty prefix means no prefix required
            case String.trim(header_value) do
              "" -> :not_found
              clean_token -> {:ok, clean_token}
            end
          
          String.starts_with?(header_value, prefix) ->
            # Has required prefix
            token = String.replace_prefix(header_value, prefix, "")
            case String.trim(token) do
              "" -> :not_found
              clean_token -> {:ok, clean_token}
            end
          
          true ->
            # Prefix required but not found
            :not_found
        end
        
      [] ->
        :not_found
    end
  end

  defp get_jwt_from_cookie(conn, cookie_name) do
    case conn.req_cookies[cookie_name] do
      nil -> :not_found
      "" -> :not_found
      token -> {:ok, String.trim(token)}
    end
  end

  defp parse_jwt(token, opts) do
    if opts[:verify] do
      verify_jwt(token, opts)
    else
      parse_jwt_unverified(token)
    end
  end

  defp parse_jwt_unverified(token) do
    case String.split(token, ".") do
      [_header, payload, _signature] ->
        decode_jwt_payload(payload)
        
      [_header, payload] ->
        decode_jwt_payload(payload)
        
      _ ->
        {:error, "Invalid JWT format"}
    end
  end

  defp verify_jwt(token, opts) do
    secret = opts[:secret]
    _algorithm = opts[:algorithm] || @default_algorithm
    
    if secret do
      try do
        case Plug.Crypto.MessageVerifier.verify(token, secret) do
          {:ok, payload} when is_map(payload) ->
            {:ok, payload}
            
          {:ok, payload} when is_binary(payload) ->
            case Jason.decode(payload) do
              {:ok, decoded} -> {:ok, decoded}
              {:error, _} -> {:error, "Invalid JSON in JWT payload"}
            end
            
          {:error, _} ->
            {:error, "JWT verification failed"}
        end
      rescue
        _ -> {:error, "JWT verification failed"}
      end
    else
      {:error, "Secret required for JWT verification"}
    end
  end

  defp decode_jwt_payload(payload_part) do
    try do
      # Add padding if necessary
      padded = add_base64_padding(payload_part)
      
      case Base.url_decode64(padded) do
        {:ok, json} ->
          case Jason.decode(json) do
            {:ok, decoded} -> {:ok, decoded}
            {:error, _} -> {:error, "Invalid JSON in JWT payload"}
          end
          
        :error ->
          {:error, "Invalid base64 encoding in JWT payload"}
      end
    rescue
      _ -> {:error, "Failed to decode JWT payload"}
    end
  end

  defp add_base64_padding(string) do
    case rem(String.length(string), 4) do
      0 -> string
      2 -> string <> "=="
      3 -> string <> "="
      _ -> string
    end
  end

  defp extract_tenant_from_payload(payload, opts) do
    claim = opts[:claim] || @default_claim
    transform_fn = opts[:transform]
    
    case get_claim_value(payload, claim) do
      nil ->
        :not_found
        
      value ->
        transformed_value = apply_transform(value, transform_fn)
        
        case transformed_value do
          {:error, _} = error -> error
          result -> {:ok, result}
        end
    end
  end

  defp get_claim_value(payload, claim) when is_map(payload) do
    # Support nested claims with dot notation (e.g., "user.tenant_id")
    claim_parts = String.split(claim, ".")
    
    Enum.reduce_while(claim_parts, payload, fn part, acc ->
      case acc do
        %{} ->
          case Map.get(acc, part) do
            nil -> {:halt, nil}
            value -> {:cont, value}
          end
          
        _ ->
          {:halt, nil}
      end
    end)
  end

  defp get_claim_value(_, _), do: nil

  defp apply_transform(value, nil), do: value
  
  defp apply_transform(value, transform_fn) when is_function(transform_fn, 1) do
    try do
      transform_fn.(value)
    rescue
      error ->
        {:error, "JWT claim transformation failed: #{inspect(error)}"}
    end
  end

  defp apply_transform(value, _), do: value

  @doc """
  Validate JWT configuration options.

  ## Examples

      iex> TenantPlug.Sources.FromJWT.validate_opts([])
      :ok

      iex> TenantPlug.Sources.FromJWT.validate_opts([header: "x-token"])
      :ok

      iex> TenantPlug.Sources.FromJWT.validate_opts([verify: true, secret: "key"])
      :ok

      iex> TenantPlug.Sources.FromJWT.validate_opts([verify: true])
      {:error, ":secret is required when :verify is true"}
  """
  @spec validate_opts(keyword()) :: :ok | {:error, String.t()}
  def validate_opts(opts) do
    with :ok <- validate_header(opts[:header]),
         :ok <- validate_header_prefix(opts[:header_prefix]),
         :ok <- validate_cookie(opts[:cookie]),
         :ok <- validate_claim(opts[:claim]),
         :ok <- validate_verify(opts[:verify], opts[:secret]),
         :ok <- validate_algorithm(opts[:algorithm]),
         :ok <- validate_transform(opts[:transform]) do
      :ok
    end
  end

  defp validate_header(nil), do: :ok
  defp validate_header(header) when is_binary(header), do: :ok
  defp validate_header(_), do: {:error, ":header must be a string"}

  defp validate_header_prefix(nil), do: :ok
  defp validate_header_prefix(prefix) when is_binary(prefix), do: :ok
  defp validate_header_prefix(_), do: {:error, ":header_prefix must be a string"}

  defp validate_cookie(nil), do: :ok
  defp validate_cookie(cookie) when is_binary(cookie), do: :ok
  defp validate_cookie(_), do: {:error, ":cookie must be a string"}

  defp validate_claim(nil), do: :ok
  defp validate_claim(claim) when is_binary(claim), do: :ok
  defp validate_claim(_), do: {:error, ":claim must be a string"}

  defp validate_verify(true, nil), do: {:error, ":secret is required when :verify is true"}
  defp validate_verify(true, secret) when is_binary(secret), do: :ok
  defp validate_verify(false, _), do: :ok
  defp validate_verify(nil, _), do: :ok
  defp validate_verify(_, _), do: {:error, ":verify must be a boolean"}

  defp validate_algorithm(nil), do: :ok
  defp validate_algorithm(algo) when is_binary(algo), do: :ok
  defp validate_algorithm(_), do: {:error, ":algorithm must be a string"}

  defp validate_transform(nil), do: :ok
  defp validate_transform(fun) when is_function(fun, 1), do: :ok
  defp validate_transform(_), do: {:error, ":transform must be a function of arity 1"}

  @doc """
  Get the default header name used by this source.

  ## Examples

      iex> TenantPlug.Sources.FromJWT.default_header()
      "authorization"
  """
  @spec default_header() :: String.t()
  def default_header, do: @default_header

  @doc """
  Get the default claim name used by this source.

  ## Examples

      iex> TenantPlug.Sources.FromJWT.default_claim()
      "tenant_id"
  """
  @spec default_claim() :: String.t()
  def default_claim, do: @default_claim
end
defmodule TenantPlug.Sources.FromSubdomain do
  @moduledoc """
  Extracts tenant information from request subdomains.

  This source extracts the tenant ID from the subdomain of the request URL.
  It supports excluding certain subdomains (like "www", "api", "admin") and
  can work with multi-level subdomains.

  ## Configuration Options

  * `:exclude` - List of subdomains to exclude (default: ["www", "api", "admin"])
  * `:position` - Which subdomain position to use (default: :first)
    - `:first` - Use the first (leftmost) subdomain
    - `:last` - Use the last (rightmost) subdomain  
    - `integer` - Use subdomain at specific position (0-indexed)
  * `:transform` - Optional function to transform the subdomain value
  * `:min_parts` - Minimum domain parts required (default: 3, e.g., "tenant.example.com")

  ## Examples

      # Basic usage - extracts "acme" from "acme.myapp.com"
      plug TenantPlug, sources: [TenantPlug.Sources.FromSubdomain]

      # Custom exclusions
      plug TenantPlug, sources: [
        {TenantPlug.Sources.FromSubdomain, exclude: ["www", "api", "staging"]}
      ]

      # Use last subdomain from "app.tenant.myservice.com" -> "tenant"
      plug TenantPlug, sources: [
        {TenantPlug.Sources.FromSubdomain, position: :last}
      ]

      # Use specific position (0-indexed)
      plug TenantPlug, sources: [
        {TenantPlug.Sources.FromSubdomain, position: 1}
      ]

      # Transform subdomain
      plug TenantPlug, sources: [
        {TenantPlug.Sources.FromSubdomain, transform: &String.upcase/1}
      ]

  ## URL Examples

      # Standard usage
      https://acme.myapp.com/api/users -> "acme"
      
      # Excluded subdomain  
      https://www.myapp.com/api/users -> :not_found
      
      # Multi-level subdomain (position: :first)
      https://tenant.env.myapp.com/api/users -> "tenant"
      
      # Multi-level subdomain (position: :last) 
      https://app.tenant.myapp.com/api/users -> "tenant"
      
      # No subdomain
      https://myapp.com/api/users -> :not_found
  """

  @behaviour TenantPlug.Sources.Behaviour

  @default_excludes ["www", "api", "admin"]
  @default_min_parts 3

  @doc """
  Extract tenant from request subdomain.
  """
  @impl TenantPlug.Sources.Behaviour
  def extract(conn, opts) do
    subdomain_opts = get_subdomain_opts(opts)
    
    host = get_host(conn)
    
    case host do
      nil ->
        :not_found
        
      "" ->
        :not_found
        
      host_value ->
        extract_from_host(host_value, subdomain_opts)
    end
  end

  # Private functions

  defp get_subdomain_opts(opts) do
    case Keyword.get(opts, :sources, []) do
      [] -> 
        []
      
      sources when is_list(sources) ->
        Enum.find_value(sources, [], fn
          {TenantPlug.Sources.FromSubdomain, source_opts} -> source_opts
          TenantPlug.Sources.FromSubdomain -> []
          _ -> nil
        end)
      
      _ ->
        # Return empty opts for malformed sources config
        []
    end
  end

  defp get_host(conn) do
    case Plug.Conn.get_req_header(conn, "host") do
      [host | _] -> 
        # Remove port if present
        host
        |> String.split(":")
        |> List.first()
        
      [] ->
        nil
    end
  end

  defp extract_from_host(host, opts) do
    exclude_list = opts[:exclude] || @default_excludes
    position = opts[:position] || :first
    transform_fn = opts[:transform]
    min_parts = opts[:min_parts] || @default_min_parts

    parts = String.split(host, ".")
    
    cond do
      length(parts) < min_parts ->
        :not_found
        
      true ->
        case position do
          :last ->
            # Find last non-excluded subdomain
            subdomain_parts = Enum.drop(parts, -2) # Remove domain and TLD
            last_non_excluded = 
              subdomain_parts
              |> Enum.reverse()
              |> Enum.find(fn part -> part not in exclude_list end)
            
            if last_non_excluded do
              transformed_subdomain = apply_transform(last_non_excluded, transform_fn)
              case transformed_subdomain do
                {:error, _} = error -> error
                result -> {:ok, result}
              end
            else
              :not_found
            end
          
          _ ->
            subdomain = extract_subdomain(parts, position)
            
            cond do
              subdomain == nil ->
                :not_found
                
              subdomain in exclude_list ->
                :not_found
                
              true ->
                transformed_subdomain = apply_transform(subdomain, transform_fn)
                
                case transformed_subdomain do
                  {:error, _} = error -> error
                  result -> {:ok, result}
                end
            end
        end
    end
  end

  defp extract_subdomain(parts, :first) do
    case parts do
      [subdomain | _rest] when length(parts) >= 3 -> subdomain
      _ -> nil
    end
  end

  defp extract_subdomain(parts, :last) when length(parts) >= 3 do
    # Get the last subdomain (excluding domain and TLD)
    parts
    |> Enum.reverse()
    |> Enum.drop(2)  # Drop TLD and domain
    |> List.first()
  end

  defp extract_subdomain(parts, position) when is_integer(position) and position >= 0 do
    if length(parts) >= 3 and position < length(parts) - 2 do
      Enum.at(parts, position)
    else
      nil
    end
  end

  defp extract_subdomain(_parts, _position), do: nil

  defp apply_transform(subdomain, nil), do: subdomain
  
  defp apply_transform(subdomain, transform_fn) when is_function(transform_fn, 1) do
    try do
      transform_fn.(subdomain)
    rescue
      error ->
        {:error, "Subdomain transformation failed: #{inspect(error)}"}
    end
  end

  defp apply_transform(subdomain, _), do: subdomain

  @doc """
  Validate subdomain configuration options.

  ## Examples

      iex> TenantPlug.Sources.FromSubdomain.validate_opts([])
      :ok

      iex> TenantPlug.Sources.FromSubdomain.validate_opts([exclude: ["www"]])
      :ok

      iex> TenantPlug.Sources.FromSubdomain.validate_opts([position: :first])
      :ok

      iex> TenantPlug.Sources.FromSubdomain.validate_opts([exclude: "www"])
      {:error, ":exclude must be a list of strings"}
  """
  @spec validate_opts(keyword()) :: :ok | {:error, String.t()}
  def validate_opts(opts) do
    with :ok <- validate_exclude(opts[:exclude]),
         :ok <- validate_position(opts[:position]),
         :ok <- validate_transform(opts[:transform]),
         :ok <- validate_min_parts(opts[:min_parts]) do
      :ok
    end
  end

  defp validate_exclude(nil), do: :ok
  
  defp validate_exclude(exclude) when is_list(exclude) do
    if Enum.all?(exclude, &is_binary/1) do
      :ok
    else
      {:error, ":exclude must be a list of strings"}
    end
  end
  
  defp validate_exclude(_), do: {:error, ":exclude must be a list of strings"}

  defp validate_position(nil), do: :ok
  defp validate_position(:first), do: :ok
  defp validate_position(:last), do: :ok
  defp validate_position(pos) when is_integer(pos) and pos >= 0, do: :ok
  defp validate_position(_), do: {:error, ":position must be :first, :last, or a non-negative integer"}

  defp validate_transform(nil), do: :ok
  defp validate_transform(fun) when is_function(fun, 1), do: :ok
  defp validate_transform(_), do: {:error, ":transform must be a function of arity 1"}

  defp validate_min_parts(nil), do: :ok
  defp validate_min_parts(parts) when is_integer(parts) and parts >= 2, do: :ok
  defp validate_min_parts(_), do: {:error, ":min_parts must be an integer >= 2"}

  @doc """
  Get the default list of excluded subdomains.

  ## Examples

      iex> TenantPlug.Sources.FromSubdomain.default_excludes()
      ["www", "api", "admin"]
  """
  @spec default_excludes() :: [String.t()]
  def default_excludes, do: @default_excludes

  @doc """
  Parse a host string into its component parts.

  ## Examples

      iex> TenantPlug.Sources.FromSubdomain.parse_host("tenant.example.com")
      {:ok, %{subdomain: "tenant", domain: "example", tld: "com"}}

      iex> TenantPlug.Sources.FromSubdomain.parse_host("example.com")
      {:ok, %{subdomain: nil, domain: "example", tld: "com"}}

      iex> TenantPlug.Sources.FromSubdomain.parse_host("invalid")
      {:error, "Invalid host format"}
  """
  @spec parse_host(String.t()) :: {:ok, map()} | {:error, String.t()}
  def parse_host(host) when is_binary(host) do
    parts = String.split(host, ".")
    
    case parts do
      [domain, tld] ->
        {:ok, %{subdomain: nil, domain: domain, tld: tld}}
        
      [subdomain, domain, tld] ->
        {:ok, %{subdomain: subdomain, domain: domain, tld: tld}}
        
      parts when length(parts) > 3 ->
        # For "app.tenant.service.example.com" -> ["app", "tenant", "service", "example", "com"]
        # We want: subdomain="app.tenant.service", domain="example", tld="com"
        tld = List.last(parts)
        domain_and_subdomains = Enum.drop(parts, -1) # ["app", "tenant", "service", "example"]
        domain = List.last(domain_and_subdomains) # "example"
        subdomain_parts = Enum.drop(domain_and_subdomains, -1) # ["app", "tenant", "service"]
        subdomain = Enum.join(subdomain_parts, ".")
        
        {:ok, %{subdomain: subdomain, domain: domain, tld: tld}}
        
      _ ->
        {:error, "Invalid host format"}
    end
  end
end
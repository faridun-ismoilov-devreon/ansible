# Быстрое решение проблемы Timeout

## Проблема
Pod'ы в Kubernetes не могут напрямую подключиться к `192.168.150.1` (HAProxy gateway).

## Решение: Используйте Kubernetes Service

### 1. Создайте Service (уже создан)

```bash
kubectl apply -f clickhouse/clickhouse-service.yaml
```

### 2. В вашем микросервисе используйте:

**Вместо:**
```csharp
var host = "192.168.150.1";  // ❌ Не работает из pod'ов
```

**Используйте:**
```csharp
// Вариант 1: Через Service (рекомендуется)
var host = "clickhouse-direct.default.svc.cluster.local";
// или просто
var host = "clickhouse-direct";

// Вариант 2: Если Service не работает, используйте прямые IP нод
var hosts = new[] {
    "192.168.150.140",
    "192.168.150.141",
    "192.168.150.142"
};
```

### 3. Проверка

```bash
# Проверить Service
kubectl get svc clickhouse-direct

# Тест из pod
kubectl run test --image=curlimages/curl --rm -i --restart=Never -- \
  curl "http://clickhouse-direct:8123/?query=SELECT+1"
```

### 4. Если Service не работает - используйте прямые IP

В вашем коде добавьте fallback на прямые IP адреса нод:

```csharp
private readonly string[] _clickHouseHosts = {
    "192.168.150.140",
    "192.168.150.141", 
    "192.168.150.142"
};

private async Task<string> ExecuteWithRetryAsync(string query)
{
    foreach (var host in _clickHouseHosts)
    {
        try
        {
            var url = $"http://{host}:8123/?query={Uri.EscapeDataString(query)}";
            var response = await _httpClient.GetAsync(url);
            if (response.IsSuccessStatusCode)
                return await response.Content.ReadAsStringAsync();
        }
        catch (Exception ex)
        {
            // Log and try next host
            Console.WriteLine($"Failed to connect to {host}: {ex.Message}");
        }
    }
    throw new Exception("All ClickHouse hosts unavailable");
}
```

## Важно: Добавьте аутентификацию!

ClickHouse требует пароль. Добавьте в connection string:

```csharp
var url = $"http://default:YOUR_PASSWORD@{host}:8123/?query={Uri.EscapeDataString(query)}";
```

Или используйте заголовок Authorization:

```csharp
var auth = Convert.ToBase64String(Encoding.ASCII.GetBytes($"default:YOUR_PASSWORD"));
_httpClient.DefaultRequestHeaders.Authorization = 
    new AuthenticationHeaderValue("Basic", auth);
```


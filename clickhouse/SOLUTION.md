# Решение проблемы Timeout при подключении к ClickHouse

## Диагностика показала:

1. ✅ HAProxy работает и слушает порты 8123 и 9000
2. ✅ Все ClickHouse ноды доступны и в статусе UP в HAProxy
3. ✅ ClickHouse требует аутентификацию (пароль)
4. ❌ Pod'ы в Kubernetes **НЕ МОГУТ** напрямую подключиться к `192.168.150.1`

## Решение: Используйте прямые IP адреса ClickHouse нод

Поскольку pod'ы не могут достичь gateway (192.168.150.1), используйте прямые IP адреса нод:

### IP адреса ClickHouse нод:
- `192.168.150.140` (ch-node-01)
- `192.168.150.141` (ch-node-02)  
- `192.168.150.142` (ch-node-03)

### Вариант 1: Одна нода (для теста)

```csharp
var clickHouseHost = "192.168.150.140";
var clickHousePort = 8123;
var url = $"http://default:YOUR_PASSWORD@{clickHouseHost}:{clickHousePort}/?query={Uri.EscapeDataString(query)}";
```

### Вариант 2: Балансировка между нодами (рекомендуется)

```csharp
public class ClickHouseClient
{
    private readonly string[] _hosts = {
        "192.168.150.140",
        "192.168.150.141",
        "192.168.150.142"
    };
    
    private readonly HttpClient _httpClient;
    private int _currentHostIndex = 0;
    
    public ClickHouseClient(string password)
    {
        _httpClient = new HttpClient
        {
            Timeout = TimeSpan.FromSeconds(300) // 5 минут
        };
        
        // Базовая аутентификация
        var auth = Convert.ToBase64String(
            Encoding.ASCII.GetBytes($"default:{password}"));
        _httpClient.DefaultRequestHeaders.Authorization = 
            new AuthenticationHeaderValue("Basic", auth);
    }
    
    public async Task<string> ExecuteQueryAsync(string query, CancellationToken ct = default)
    {
        // Round-robin между нодами
        var host = _hosts[_currentHostIndex];
        _currentHostIndex = (_currentHostIndex + 1) % _hosts.Length;
        
        var url = $"http://{host}:8123/?query={Uri.EscapeDataString(query)}";
        
        try
        {
            var response = await _httpClient.GetAsync(url, ct);
            response.EnsureSuccessStatusCode();
            return await response.Content.ReadAsStringAsync(ct);
        }
        catch (Exception ex)
        {
            // Retry на следующей ноде
            return await ExecuteQueryAsync(query, ct);
        }
    }
}
```

### Вариант 3: С retry на всех нодах

```csharp
public async Task<string> ExecuteQueryWithRetryAsync(string query, CancellationToken ct = default)
{
    var exceptions = new List<Exception>();
    
    foreach (var host in _hosts)
    {
        try
        {
            var url = $"http://{host}:8123/?query={Uri.EscapeDataString(query)}";
            var response = await _httpClient.GetAsync(url, ct);
            response.EnsureSuccessStatusCode();
            return await response.Content.ReadAsStringAsync(ct);
        }
        catch (Exception ex)
        {
            exceptions.Add(ex);
            // Продолжить на следующей ноде
            continue;
        }
    }
    
    throw new AggregateException("All ClickHouse hosts failed", exceptions);
}
```

## Важно: Настройте аутентификацию!

ClickHouse требует пароль. Получите его из конфигурации:

```bash
# На ClickHouse ноде
ssh root@192.168.150.140 "cat /etc/clickhouse-server/users.d/default-password.xml"
```

Или используйте пароль по умолчанию (если не меняли): `clickhouse123`

## Конфигурация appsettings.json

```json
{
  "ClickHouse": {
    "Hosts": [
      "192.168.150.140",
      "192.168.150.141",
      "192.168.150.142"
    ],
    "HttpPort": 8123,
    "NativePort": 9000,
    "Database": "default",
    "Username": "default",
    "Password": "YOUR_PASSWORD",
    "Timeout": 300,
    "ConnectionTimeout": 30
  }
}
```

## Проверка подключения

```bash
# Из любого pod в кластере
kubectl run test --image=curlimages/curl --rm -i --restart=Never -- \
  curl "http://default:YOUR_PASSWORD@192.168.150.140:8123/?query=SELECT+1"
```

## Почему не работает 192.168.150.1?

Pod'ы в Kubernetes используют OVN сеть (10.x.x.x) и не имеют прямого маршрута к gateway виртуальной сети (192.168.150.1). Поэтому нужно использовать прямые IP адреса нод, которые доступны через сеть хоста.

## Альтернативное решение: Использовать NodePort Service

Если прямые IP не работают, можно создать NodePort Service:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: clickhouse-nodeport
spec:
  type: NodePort
  ports:
  - port: 8123
    targetPort: 8123
    nodePort: 30123
  selector:
    app: clickhouse-proxy  # Нужен proxy pod на нодах
```

Но это более сложное решение, требующее дополнительных компонентов.


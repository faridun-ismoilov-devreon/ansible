# Troubleshooting: HttpClient Timeout при подключении к ClickHouse

## Проблема
```
System.Threading.Tasks.TaskCanceledException: The request was canceled due to the configured HttpClient.Timeout of 120 seconds elapsing
```

## Диагностика

### 1. Проверка доступности HAProxy

```bash
# С хоста
ssh root@37.27.173.224 "curl -v --max-time 5 'http://192.168.150.1:8123/?query=SELECT+1'"

# Проверка статуса HAProxy
ssh root@37.27.173.224 "systemctl status haproxy"
ssh root@37.27.173.224 "netstat -tlnp | grep -E '8123|9000'"
```

### 2. Проверка статуса ClickHouse нод в HAProxy

```bash
ssh root@37.27.173.224 "echo 'show servers state' | socat stdio /run/haproxy/admin.sock | grep clickhouse"
```

Все ноды должны быть в статусе `UP` (2).

### 3. Проверка из Kubernetes pod

```bash
# Тест подключения
kubectl run clickhouse-test --image=curlimages/curl --rm -i --restart=Never -- \
  curl -v --max-time 10 --connect-timeout 5 \
  "http://192.168.150.1:8123/?query=SELECT+1"

# Тест сетевой связности
kubectl run network-test --image=alpine --rm -i --restart=Never -- \
  sh -c "ping -c 2 192.168.150.1 && nc -zv -w 5 192.168.150.1 8123"
```

### 4. Проверка доступности ClickHouse нод напрямую

```bash
# С хоста
for ip in 192.168.150.140 192.168.150.141 192.168.150.142; do
  echo "Testing $ip:8123"
  curl -v --max-time 5 "http://$ip:8123/?query=SELECT+1"
done
```

## Возможные причины и решения

### Проблема 1: Pod'ы не могут достичь 192.168.150.1

**Симптомы:**
- Timeout при подключении
- Connection refused
- Network unreachable

**Решение:**

#### Вариант A: Использовать Kubernetes Service

Создайте Service для ClickHouse:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: clickhouse
  namespace: default
spec:
  type: ExternalName
  externalName: 192.168.150.1
  ports:
  - name: http
    port: 8123
    targetPort: 8123
  - name: native
    port: 9000
    targetPort: 9000
```

Используйте в приложении:
```csharp
var host = "clickhouse.default.svc.cluster.local"; // или просто "clickhouse"
var port = 8123;
```

#### Вариант B: Использовать Endpoints с прямым IP

```yaml
apiVersion: v1
kind: Service
metadata:
  name: clickhouse-direct
spec:
  clusterIP: None
  ports:
  - port: 8123
    name: http
---
apiVersion: v1
kind: Endpoints
metadata:
  name: clickhouse-direct
subsets:
- addresses:
  - ip: 192.168.150.1
  ports:
  - port: 8123
    name: http
```

#### Вариант C: Прямое подключение к нодам (если Service не работает)

```csharp
// Используйте прямые IP адреса нод
var hosts = new[] {
    "192.168.150.140",
    "192.168.150.141", 
    "192.168.150.142"
};
```

### Проблема 2: ClickHouse требует аутентификацию

**Симптомы:**
- `Authentication failed: password is incorrect`
- `REQUIRED_PASSWORD`

**Решение:**

Добавьте аутентификацию в connection string:

```csharp
// HTTP
var url = "http://default:YOUR_PASSWORD@192.168.150.1:8123/";

// Native (clickhouse-client)
var connectionString = "Host=192.168.150.1;Port=9000;Username=default;Password=YOUR_PASSWORD;Database=default";
```

### Проблема 3: Firewall блокирует соединения

**Проверка:**

```bash
# Проверить iptables на хосте
ssh root@37.27.173.224 "iptables -L -n | grep -E '8123|9000'"

# Проверить сетевые политики Kubernetes
kubectl get networkpolicies -A
```

**Решение:**

Если нужно, добавьте правила firewall или NetworkPolicy.

### Проблема 4: Неправильный timeout в HttpClient

**Решение:**

Увеличьте timeout или добавьте retry логику:

```csharp
var client = new HttpClient
{
    Timeout = TimeSpan.FromSeconds(300) // 5 минут вместо 120 секунд
};

// Или с retry policy
var policy = Policy
    .Handle<TaskCanceledException>()
    .Or<HttpRequestException>()
    .WaitAndRetryAsync(
        retryCount: 3,
        sleepDurationProvider: retryAttempt => TimeSpan.FromSeconds(Math.Pow(2, retryAttempt)),
        onRetry: (outcome, timespan, retryCount, context) =>
        {
            Console.WriteLine($"Retry {retryCount} after {timespan}");
        });
```

## Рекомендуемая конфигурация для .NET приложения

### appsettings.json

```json
{
  "ClickHouse": {
    "Host": "192.168.150.1",
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

### C# код

```csharp
public class ClickHouseService
{
    private readonly HttpClient _httpClient;
    private readonly string _baseUrl;
    
    public ClickHouseService(IConfiguration configuration)
    {
        var config = configuration.GetSection("ClickHouse");
        _baseUrl = $"http://{config["Host"]}:{config["HttpPort"]}";
        
        _httpClient = new HttpClient
        {
            Timeout = TimeSpan.FromSeconds(config.GetValue<int>("Timeout", 300))
        };
        
        // Добавить базовую аутентификацию если нужно
        var auth = Convert.ToBase64String(
            Encoding.ASCII.GetBytes($"{config["Username"]}:{config["Password"]}"));
        _httpClient.DefaultRequestHeaders.Authorization = 
            new AuthenticationHeaderValue("Basic", auth);
    }
    
    public async Task<string> ExecuteQueryAsync(string query, CancellationToken cancellationToken = default)
    {
        try
        {
            var response = await _httpClient.PostAsync(
                $"{_baseUrl}/?query={Uri.EscapeDataString(query)}",
                null,
                cancellationToken);
            
            response.EnsureSuccessStatusCode();
            return await response.Content.ReadAsStringAsync();
        }
        catch (TaskCanceledException ex) when (ex.InnerException is TimeoutException)
        {
            throw new Exception($"ClickHouse query timeout after {_httpClient.Timeout.TotalSeconds} seconds", ex);
        }
    }
}
```

## Быстрая проверка

Выполните этот скрипт для полной диагностики:

```bash
./clickhouse/test-connection.sh
```

## Следующие шаги

1. ✅ Проверьте доступность HAProxy (должен быть UP)
2. ✅ Проверьте статус ClickHouse нод в HAProxy (все должны быть UP)
3. ✅ Проверьте подключение из pod (может потребоваться Service)
4. ✅ Добавьте аутентификацию если требуется
5. ✅ Увеличьте timeout в HttpClient если нужно
6. ✅ Проверьте firewall правила


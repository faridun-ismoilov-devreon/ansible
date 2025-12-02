# Простое решение: Используйте прямые IP адреса нод

## Проблема

У вас уже есть HAProxy на хосте (`192.168.150.1`), но pod'ы в Kubernetes не могут к нему подключиться из-за сетевой изоляции OVN.

## Решение: Используйте прямые IP адреса ClickHouse нод

**Не нужен дополнительный HAProxy!** Просто подключайтесь напрямую к нодам:

### IP адреса ваших ClickHouse нод:
- `192.168.150.140` (ch-node-01)
- `192.168.150.141` (ch-node-02)
- `192.168.150.142` (ch-node-03)

## Для ClickHouse.Driver

### Вариант 1: Простой - одна нода

```csharp
using ClickHouse.Driver.ADO;

var connectionString = "Host=192.168.150.140;" +  // Прямой IP ноды
    "Port=8123;" +
    "Database=default;" +
    "Username=default;" +
    "Password=your_password;";

using var connection = new ClickHouseConnection(connectionString);
```

### Вариант 2: С балансировкой (рекомендуется)

```csharp
public class ClickHouseService
{
    private readonly string[] _hosts = {
        "192.168.150.140",
        "192.168.150.141",
        "192.168.150.142"
    };
    private int _currentIndex = 0;
    private readonly object _lock = new object();
    
    private string GetNextHost()
    {
        lock (_lock)
        {
            var host = _hosts[_currentIndex];
            _currentIndex = (_currentIndex + 1) % _hosts.Length;
            return host;
        }
    }
    
    public async Task<T> ExecuteAsync<T>(string query)
    {
        // Пробуем все ноды по очереди
        foreach (var host in _hosts)
        {
            try
            {
                var connectionString = $"Host={host};Port=8123;Database=default;Username=default;Password=your_password;";
                await using var connection = new ClickHouseConnection(connectionString);
                await connection.OpenAsync();
                return await connection.ExecuteScalarAsync<T>(query);
            }
            catch (Exception ex)
            {
                // Пробуем следующую ноду
                continue;
            }
        }
        throw new Exception("All ClickHouse nodes unavailable");
    }
}
```

## Почему это работает?

1. **Pod'ы могут достичь ноды напрямую** - они в одной сети `192.168.150.0/24`
2. **Репликация автоматическая** - данные синхронизируются между нодами через Keeper
3. **Отказоустойчивость** - если одна нода упадет, используйте другие
4. **Балансировка нагрузки** - распределяйте запросы между нодами

## Преимущества прямого подключения:

✅ **Простота** - не нужен дополнительный HAProxy  
✅ **Меньше точек отказа** - нет промежуточного слоя  
✅ **Прямой доступ** - pod'ы напрямую к нодам  
✅ **Автоматическая репликация** - ClickHouse сам синхронизирует данные  

## appsettings.json

```json
{
  "ClickHouse": {
    "Hosts": [
      "192.168.150.140",
      "192.168.150.141",
      "192.168.150.142"
    ],
    "Port": 8123,
    "Database": "default",
    "Username": "default",
    "Password": "your_password"
  }
}
```

## Итог

**Не нужен дополнительный HAProxy!** Используйте прямые IP адреса нод в вашем .NET приложении. Репликация происходит автоматически на уровне ClickHouse.


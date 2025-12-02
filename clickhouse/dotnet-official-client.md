# Официальный .NET клиент ClickHouse.Driver

## Официальная библиотека

**NuGet:** `ClickHouse.Driver`  
**Документация:** https://clickhouse.com/docs/integrations/csharp  
**GitHub:** https://github.com/ClickHouse/clickhouse-dotnet

⚠️ **Важно:** Ранее библиотека называлась `ClickHouse.Client`, но была переименована в `ClickHouse.Driver`.

## Установка

```bash
dotnet add package ClickHouse.Driver
```

## Поддержка нескольких хостов

Согласно официальной документации, параметр `Host` в connection string принимает один адрес. Однако, для работы с кластером рекомендуется использовать один из подходов:

### Вариант 1: Использовать один хост (HAProxy)

Если у вас есть балансировщик (например, HAProxy на `192.168.150.1`):

```csharp
using ClickHouse.Driver.ADO;

var connectionString = "Host=192.168.150.1;" +
    "Port=8123;" +
    "Database=default;" +
    "Username=default;" +
    "Password=your_password;";

using var connection = new ClickHouseConnection(connectionString);
await connection.OpenAsync();
```

### Вариант 2: Собственная реализация с балансировкой

Поскольку официальный клиент не поддерживает несколько хостов напрямую в connection string, можно реализовать свой wrapper:

```csharp
using ClickHouse.Driver.ADO;
using Microsoft.Extensions.Logging;

public class ClickHouseClusterClient
{
    private readonly string[] _hosts;
    private readonly int _port;
    private readonly string _database;
    private readonly string _username;
    private readonly string _password;
    private readonly ILogger<ClickHouseClusterClient> _logger;
    private int _currentHostIndex = 0;
    private readonly object _lock = new object();
    
    public ClickHouseClusterClient(
        string[] hosts,
        int port,
        string database,
        string username,
        string password,
        ILogger<ClickHouseClusterClient> logger)
    {
        _hosts = hosts ?? throw new ArgumentNullException(nameof(hosts));
        _port = port;
        _database = database;
        _username = username;
        _password = password;
        _logger = logger;
    }
    
    // Round-robin выбор хоста
    private string GetNextHost()
    {
        lock (_lock)
        {
            var host = _hosts[_currentHostIndex];
            _currentHostIndex = (_currentHostIndex + 1) % _hosts.Length;
            return host;
        }
    }
    
    // Создание подключения с retry на всех хостах
    private async Task<ClickHouseConnection> CreateConnectionAsync(CancellationToken cancellationToken = default)
    {
        var exceptions = new List<Exception>();
        
        // Пробуем все хосты по очереди
        foreach (var host in _hosts)
        {
            try
            {
                var connectionString = $"Host={host};Port={_port};Database={_database};" +
                    $"Username={_username};Password={_password};";
                
                var connection = new ClickHouseConnection(connectionString);
                await connection.OpenAsync(cancellationToken);
                
                _logger.LogInformation("Connected to ClickHouse host: {Host}", host);
                return connection;
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Failed to connect to ClickHouse host: {Host}", host);
                exceptions.Add(ex);
                continue;
            }
        }
        
        throw new AggregateException("All ClickHouse hosts unavailable", exceptions);
    }
    
    // Выполнение запроса с автоматическим failover
    public async Task<T> ExecuteScalarAsync<T>(string query, CancellationToken cancellationToken = default)
    {
        var exceptions = new List<Exception>();
        
        foreach (var host in _hosts)
        {
            try
            {
                var connectionString = $"Host={host};Port={_port};Database={_database};" +
                    $"Username={_username};Password={_password};";
                
                await using var connection = new ClickHouseConnection(connectionString);
                await connection.OpenAsync(cancellationToken);
                
                var result = await connection.ExecuteScalarAsync<T>(query, cancellationToken);
                return result;
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Query failed on host {Host}: {Error}", host, ex.Message);
                exceptions.Add(ex);
                continue;
            }
        }
        
        throw new AggregateException("Query failed on all hosts", exceptions);
    }
    
    // Выполнение запроса с возвратом результата
    public async Task<List<T>> QueryAsync<T>(
        string query, 
        Func<System.Data.Common.DbDataReader, T> mapper,
        CancellationToken cancellationToken = default)
    {
        var exceptions = new List<Exception>();
        
        foreach (var host in _hosts)
        {
            try
            {
                var connectionString = $"Host={host};Port={_port};Database={_database};" +
                    $"Username={_username};Password={_password};";
                
                await using var connection = new ClickHouseConnection(connectionString);
                await connection.OpenAsync(cancellationToken);
                
                var command = connection.CreateCommand();
                command.CommandText = query;
                
                var results = new List<T>();
                await using var reader = await command.ExecuteReaderAsync(cancellationToken);
                
                while (await reader.ReadAsync(cancellationToken))
                {
                    results.Add(mapper(reader));
                }
                
                return results;
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Query failed on host {Host}: {Error}", host, ex.Message);
                exceptions.Add(ex);
                continue;
            }
        }
        
        throw new AggregateException("Query failed on all hosts", exceptions);
    }
    
    // INSERT с retry
    public async Task InsertAsync(string query, CancellationToken cancellationToken = default)
    {
        var exceptions = new List<Exception>();
        
        // Для INSERT достаточно успешно выполнить на одной ноде
        // Репликация произойдет автоматически
        foreach (var host in _hosts)
        {
            try
            {
                var connectionString = $"Host={host};Port={_port};Database={_database};" +
                    $"Username={_username};Password={_password};";
                
                await using var connection = new ClickHouseConnection(connectionString);
                await connection.OpenAsync(cancellationToken);
                
                var command = connection.CreateCommand();
                command.CommandText = query;
                await command.ExecuteNonQueryAsync(cancellationToken);
                
                _logger.LogInformation("Insert successful on host: {Host}", host);
                return; // Успешно вставили
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Insert failed on host {Host}: {Error}", host, ex.Message);
                exceptions.Add(ex);
                continue;
            }
        }
        
        throw new AggregateException("Insert failed on all hosts", exceptions);
    }
}
```

### Использование

```csharp
// Регистрация в DI
services.AddSingleton<ClickHouseClusterClient>(provider =>
{
    var config = provider.GetRequiredService<IConfiguration>();
    var logger = provider.GetRequiredService<ILogger<ClickHouseClusterClient>>();
    
    var hosts = config.GetSection("ClickHouse:Hosts").Get<string[]>() 
        ?? new[] { "192.168.150.140", "192.168.150.141", "192.168.150.142" };
    
    return new ClickHouseClusterClient(
        hosts,
        config.GetValue<int>("ClickHouse:Port", 8123),
        config.GetValue<string>("ClickHouse:Database", "default"),
        config.GetValue<string>("ClickHouse:Username", "default"),
        config.GetValue<string>("ClickHouse:Password"),
        logger
    );
});

// Использование
public class MyService
{
    private readonly ClickHouseClusterClient _clickHouse;
    
    public MyService(ClickHouseClusterClient clickHouse)
    {
        _clickHouse = clickHouse;
    }
    
    public async Task<List<Event>> GetEventsAsync()
    {
        return await _clickHouse.QueryAsync<Event>(
            "SELECT * FROM mydb.events ORDER BY timestamp DESC LIMIT 100",
            reader => new Event
            {
                Id = reader.GetInt64("id"),
                Message = reader.GetString("message"),
                Timestamp = reader.GetDateTime("timestamp")
            }
        );
    }
    
    public async Task InsertEventAsync(Event evt)
    {
        var query = $"INSERT INTO mydb.events (id, message, timestamp) VALUES ({evt.Id}, '{evt.Message}', '{evt.Timestamp:yyyy-MM-dd HH:mm:ss}')";
        await _clickHouse.InsertAsync(query);
    }
}
```

## Полный пример с appsettings.json

### appsettings.json

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
    "Password": "your_password",
    "Timeout": 300
  }
}
```

### Program.cs

```csharp
using ClickHouse.Driver.ADO;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

var builder = Host.CreateApplicationBuilder(args);

// Регистрация ClickHouse клиента
builder.Services.AddSingleton<ClickHouseClusterClient>(provider =>
{
    var config = provider.GetRequiredService<IConfiguration>();
    var logger = provider.GetRequiredService<ILogger<ClickHouseClusterClient>>();
    
    var hosts = config.GetSection("ClickHouse:Hosts").Get<string[]>() 
        ?? new[] { "192.168.150.140", "192.168.150.141", "192.168.150.142" };
    
    return new ClickHouseClusterClient(
        hosts,
        config.GetValue<int>("ClickHouse:Port", 8123),
        config.GetValue<string>("ClickHouse:Database", "default"),
        config.GetValue<string>("ClickHouse:Username", "default"),
        config.GetValue<string>("ClickHouse:Password"),
        logger
    );
});

var host = builder.Build();
host.Run();
```

## Быстрый старт (один хост)

Если используете HAProxy или один хост:

```csharp
using ClickHouse.Driver.ADO;

var connectionString = "Host=192.168.150.1;" +  // HAProxy gateway
    "Port=8123;" +
    "Database=default;" +
    "Username=default;" +
    "Password=your_password;";

using var connection = new ClickHouseConnection(connectionString);
await connection.OpenAsync();

var version = await connection.ExecuteScalarAsync<string>("SELECT version()");
Console.WriteLine($"ClickHouse version: {version}");
```

## Параметры connection string

Согласно [официальной документации](https://clickhouse.com/docs/integrations/csharp):

| Параметр | Описание | По умолчанию |
|----------|----------|--------------|
| Host | Адрес сервера ClickHouse | localhost |
| Port | Порт сервера | 8123 или 8443 (зависит от Protocol) |
| Database | Начальная база данных | default |
| Username | Имя пользователя | default |
| Password | Пароль | _(пусто)_ |
| Protocol | Протокол (http или https) | http |
| Compression | Включить Gzip сжатие | true |
| Timeout | HTTP timeout (секунды) | 120 |

## Рекомендации

1. **Для кластера:** Используйте собственный wrapper с балансировкой между хостами (как показано выше)
2. **Для одного хоста:** Используйте напрямую `ClickHouseConnection`
3. **Для HAProxy:** Подключайтесь к gateway (`192.168.150.1`)

## Важные замечания

- Официальный клиент `ClickHouse.Driver` не поддерживает несколько хостов в одном connection string
- Для кластера нужно реализовать свой wrapper с retry логикой
- Репликация происходит автоматически на уровне ClickHouse - вам не нужно об этом беспокоиться
- При INSERT достаточно успешно выполнить на одной ноде - данные автоматически реплицируются


using System.Text.Json;

using Microsoft.AspNetCore.Http;

namespace eShopLite.StoreFx.Services
{
    public interface ISessionStore
    {
        T Get<T>(string key) where T : class;
        void Set<T>(string key, T value) where T : class;
        void Remove(string key);
    }

    /// <summary>
    /// The only place that touches session state. ASP.NET Core sessions store bytes, so values
    /// round-trip through JSON instead of living in memory as object references.
    /// </summary>
    public class HttpContextSessionStore : ISessionStore
    {
        private readonly IHttpContextAccessor _httpContextAccessor;

        public HttpContextSessionStore(IHttpContextAccessor httpContextAccessor)
        {
            _httpContextAccessor = httpContextAccessor;
        }

        private ISession Session => _httpContextAccessor.HttpContext?.Session;

        public T Get<T>(string key) where T : class
        {
            var json = Session?.GetString(key);

            return json == null ? null : JsonSerializer.Deserialize<T>(json);
        }

        public void Set<T>(string key, T value) where T : class
        {
            Session?.SetString(key, JsonSerializer.Serialize(value));
        }

        public void Remove(string key)
        {
            Session?.Remove(key);
        }
    }
}

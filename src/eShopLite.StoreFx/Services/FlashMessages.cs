namespace eShopLite.StoreFx.Services
{
    public class FlashMessage
    {
        public string Kind { get; set; }
        public string Text { get; set; }
    }

    /// <summary>
    /// One-shot message carried across a redirect (the role TempData played under MVC).
    /// </summary>
    public interface IFlashMessages
    {
        void Set(string kind, string text);
        FlashMessage Take();
    }

    public class SessionFlashMessages : IFlashMessages
    {
        private const string SessionKey = "eShopLite.Flash";

        private readonly ISessionStore _session;

        public SessionFlashMessages(ISessionStore session)
        {
            _session = session;
        }

        public void Set(string kind, string text)
        {
            _session.Set(SessionKey, new FlashMessage { Kind = kind, Text = text });
        }

        public FlashMessage Take()
        {
            var message = _session.Get<FlashMessage>(SessionKey);
            if (message != null)
            {
                _session.Remove(SessionKey);
            }

            return message;
        }
    }
}

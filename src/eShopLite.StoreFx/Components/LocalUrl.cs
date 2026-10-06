using System;

namespace eShopLite.StoreFx.Components
{
    public static class LocalUrl
    {
        /// <summary>
        /// Same rules as MVC's Url.IsLocalUrl: an app-relative path, never "//host" or "/\host".
        /// </summary>
        public static bool IsLocal(string url)
        {
            if (string.IsNullOrEmpty(url))
            {
                return false;
            }

            if (url[0] == '/')
            {
                return url.Length == 1 || (url[1] != '/' && url[1] != '\\' && !HasControlCharacter(url));
            }

            if (url[0] == '~' && url.Length > 1 && url[1] == '/')
            {
                return url.Length == 2 || (url[2] != '/' && url[2] != '\\' && !HasControlCharacter(url));
            }

            return false;
        }

        /// <summary>Returns <paramref name="url"/> as a root-relative path if it is local, otherwise "/".</summary>
        public static string OrHome(string url)
        {
            if (!IsLocal(url))
            {
                return "/";
            }

            return url[0] == '~' ? url.Substring(1) : url;
        }

        private static bool HasControlCharacter(string value)
        {
            foreach (var c in value)
            {
                if (char.IsControl(c))
                {
                    return true;
                }
            }

            return false;
        }
    }
}

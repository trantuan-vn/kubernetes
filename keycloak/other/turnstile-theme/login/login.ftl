<!DOCTYPE html>
<html>
<head>
    <title>${msg("loginTitle", realm.displayName)}</title>
    <link rel="stylesheet" href="${url.resourcesPath}/css/login.css" />
    <script src="https://challenges.cloudflare.com/turnstile/v0/api.js" async defer></script>
</head>
<body>
    <div class="kc-login">
        <div class="kc-logo">
            <img src="${url.resourcesPath}/img/keycloak-logo.png" alt="Keycloak" />
        </div>
        <div class="kc-form">
            <h2>${msg("loginTitleHtml", realm.displayNameHtml)}</h2>
            <#if message?has_content>
                <div class="alert alert-${message.type}">
                    ${kcSanitize(msg(message.summary))}
                </div>
            </#if>
            <form id="kc-form-login" action="${url.loginAction}" method="post">
                <div class="form-group">
                    <label for="username">${msg("loginUsername")}</label>
                    <input id="username" name="username" type="text" autocomplete="username" />
                </div>
                <div class="form-group">
                    <label for="password">${msg("loginPassword")}</label>
                    <input id="password" name="password" type="password" autocomplete="current-password" />
                </div>
                <div class="form-group">
                    <div id="turnstile-container"></div>
                    <input type="hidden" name="cf-turnstile-response" id="cf-turnstile-response" />
                </div>
                <div class="form-group">
                    <input type="submit" value="${msg("doLogIn")}" />
                </div>
            </form>
            <#if realm.password && realm.registrationAllowed>
                <a href="${url.registrationUrl}">${msg("doRegister")}</a>
            </#if>
            <#if realm.password && realm.resetPasswordAllowed>
                <a href="${url.loginResetCredentialsUrl}">${msg("doForgotPassword")}</a>
            </#if>
            <#if social.providers??>
                <div class="kc-social-providers">
                    <#list social.providers as p>
                        <a href="${p.loginUrl}" class="kc-social-${p.alias}">${p.displayName}</a>
                    </#list>
                </div>
            </#if>
        </div>
    </div>
    <script>
        // Đợi Turnstile API sẵn sàng
        window.onload = function () {
            turnstile.render('#turnstile-container', {
                sitekey: 'YOUR_SITE_KEY',
                theme: 'auto',
                size: 'normal',
                'refresh-expired': 'auto',
                callback: function (token) {
                    console.log(`Challenge Success ${token}`);
                    // Điền token vào trường ẩn
                    document.getElementById('cf-turnstile-response').value = token;
                },
                'error-callback': function (error) {
                    console.error(`Turnstile Error: ${error}`);
                    // Có thể hiển thị thông báo lỗi cho người dùng
                    alert('Failed to verify with Turnstile. Please try again.');
                },
                'timeout-callback': function () {
                    console.log('Turnstile token timed out');
                    // Có thể yêu cầu làm mới widget
                    turnstile.reset('#turnstile-container');
                }
            });
        };
    </script>
</body>
</html>
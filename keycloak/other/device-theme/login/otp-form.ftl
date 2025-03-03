<#import "/template.ftl" as layout>
<@layout.registrationLayout>
    <h1>Verify New Device</h1>
    <p>${msg("message")}</p>
    <#if messages?has_content>
        <p style="color:red">${messages.get(0)}</p>
    </#if>
    <form action="${url.loginAction}" method="post">
        <input type="text" name="otp" placeholder="Enter OTP" />
        <button type="submit">Submit</button>
    </form>
</@layout.registrationLayout>
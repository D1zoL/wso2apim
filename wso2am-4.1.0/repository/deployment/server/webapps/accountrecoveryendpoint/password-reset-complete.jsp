<%--
  ~ Copyright (c) 2016, WSO2 Inc. (http://www.wso2.org) All Rights Reserved.
  ~
  ~  WSO2 Inc. licenses this file to you under the Apache License,
  ~  Version 2.0 (the "License"); you may not use this file except
  ~  in compliance with the License.
  ~  You may obtain a copy of the License at
  ~
  ~    http://www.apache.org/licenses/LICENSE-2.0
  ~
  ~ Unless required by applicable law or agreed to in writing,
  ~ software distributed under the License is distributed on an
  ~ "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
  ~ KIND, either express or implied.  See the License for the
  ~ specific language governing permissions and limitations
  ~ under the License.
  --%>
<%@ page import="org.apache.commons.lang.StringUtils" %>
<%@ page import="org.wso2.carbon.identity.mgt.endpoint.util.IdentityManagementEndpointConstants" %>
<%@ page import="org.wso2.carbon.identity.mgt.endpoint.util.IdentityManagementEndpointUtil" %>
<%@ page import="org.wso2.carbon.identity.mgt.endpoint.util.client.ApiException" %>
<%@ page import="org.wso2.carbon.identity.mgt.endpoint.util.client.api.NotificationApi" %>
<%@ page import="org.wso2.carbon.identity.mgt.endpoint.util.client.model.Error" %>
<%@ page import="org.wso2.carbon.identity.mgt.endpoint.util.client.model.Property" %>
<%@ page import="org.wso2.carbon.identity.mgt.endpoint.util.client.model.ResetPasswordRequest" %>
<%@ page import="org.wso2.carbon.identity.mgt.endpoint.util.client.model.User" %>
<%@ page import="org.wso2.carbon.identity.core.util.IdentityTenantUtil" %>
<%@ page import="java.io.File" %>
<%@ page import="java.net.URISyntaxException" %>
<%@ page import="java.net.URLEncoder" %>
<%@ page import="java.util.ArrayList" %>
<%@ page import="java.util.HashMap" %>
<%@ page import="java.util.List" %>
<%@ page import="java.util.Map" %>
<%@ page import="javax.servlet.http.Cookie" %>
<%@ page import="java.util.Base64" %>
<%@ page import="org.wso2.carbon.core.util.SignatureUtil" %>
<%@ page import="org.json.simple.JSONObject" %>
<%@ page import="org.owasp.encoder.Encode" %>
<%@ page import="org.wso2.carbon.identity.recovery.util.Utils" %>
<%@ page import="org.wso2.carbon.identity.application.authentication.framework.util.FrameworkUtils" %>

<jsp:directive.include file="includes/localize.jsp"/>
<jsp:directive.include file="tenant-resolve.jsp"/>

<%
    String ERROR_MESSAGE = "errorMsg";
    String ERROR_CODE = "errorCode";
    String PASSWORD_RESET_PAGE = "password-reset.jsp";
    String AUTO_LOGIN_COOKIE_NAME = "ALOR";
    String passwordHistoryErrorCode = "22001";
    String passwordPatternErrorCode = "20035";
    String confirmationKey =
            IdentityManagementEndpointUtil.getStringValue(request.getSession().getAttribute("confirmationKey"));
    String newPassword = request.getParameter("reset-password");
    String callback = request.getParameter("callback");
    String sessionDataKey = request.getParameter("sessionDataKey");
    String username = null;
    boolean isAutoLoginEnable = Boolean.parseBoolean(Utils.getConnectorConfig("Recovery.AutoLogin.Enable",
            tenantDomain));

    if (StringUtils.isBlank(callback)) {
        callback = IdentityManagementEndpointUtil.getUserPortalUrl(
                application.getInitParameter(IdentityManagementEndpointConstants.ConfigConstants.USER_PORTAL_URL));
    }

    if (StringUtils.isNotBlank(newPassword)) {
        NotificationApi notificationApi = new NotificationApi();
        ResetPasswordRequest resetPasswordRequest = new ResetPasswordRequest();
        List<Property> properties = new ArrayList<Property>();
        Property property = new Property();
        property.setKey("callback");
        property.setValue(URLEncoder.encode(callback, "UTF-8"));
        properties.add(property);

        Property tenantProperty = new Property();
        tenantProperty.setKey(IdentityManagementEndpointConstants.TENANT_DOMAIN);
        if (tenantDomain == null) {
            tenantDomain = IdentityManagementEndpointConstants.SUPER_TENANT;
        }
        tenantProperty.setValue(URLEncoder.encode(tenantDomain, "UTF-8"));
        properties.add(tenantProperty);

        resetPasswordRequest.setKey(confirmationKey);
        resetPasswordRequest.setPassword(newPassword);
        resetPasswordRequest.setProperties(properties);

        try {
            User user = notificationApi.setUserPasswordPost(resetPasswordRequest);
            username = user.getUsername();
            String userStoreDomain = user.getRealm();

            if (isAutoLoginEnable) {
                Map<String, String> queryMap = extractQueryParamsFromURL(callback);
                sessionDataKey = queryMap.get("sessionDataKey");
                String referer = request.getHeader("referer");
                String refererParams = referer.substring(referer.indexOf("?") + 1);
                String[] parameterList = refererParams.split("&");
                for (String param : parameterList) {
                    if (param.contains("=")) {
                        String key = param.substring(0, param.indexOf("="));
                        String value = param.substring(param.indexOf("=") + 1);
                        queryMap.put(key, value);
                    }
                }
                if (userStoreDomain != null) {
                  username = userStoreDomain + "/" + username;
                }
                String signature = Base64.getEncoder().encodeToString(SignatureUtil.doSignature(username));
                JSONObject cookieValueInJson = new JSONObject();
                cookieValueInJson.put("username", username);
                cookieValueInJson.put("signature", signature);
                Cookie cookie = new Cookie(AUTO_LOGIN_COOKIE_NAME,
                        Base64.getEncoder().encodeToString(cookieValueInJson.toString().getBytes()));
                cookie.setPath("/");
                cookie.setSecure(true);
                cookie.setMaxAge(300);
                response.addCookie(cookie);
            }
        } catch (ApiException e) {

            Error error = IdentityManagementEndpointUtil.buildError(e);
            IdentityManagementEndpointUtil.addErrorInformation(request, error);
            if (error != null) {
                request.setAttribute(ERROR_MESSAGE, error.getDescription());
                request.setAttribute(ERROR_CODE, error.getCode());
                if (passwordHistoryErrorCode.equals(error.getCode()) ||
                        passwordPatternErrorCode.equals(error.getCode())) {
                    String i18Resource = IdentityManagementEndpointUtil.i18n(recoveryResourceBundle, error.getCode());
                    if (!i18Resource.equals(error.getCode())) {
                        request.setAttribute(ERROR_MESSAGE, i18Resource);
                    }
                    request.setAttribute(IdentityManagementEndpointConstants.TENANT_DOMAIN, tenantDomain);
                    request.setAttribute(IdentityManagementEndpointConstants.CALLBACK, callback);
                    request.getRequestDispatcher(PASSWORD_RESET_PAGE).forward(request, response);
                    return;
                }
            }
            request.getRequestDispatcher("error.jsp").forward(request, response);
            return;
        }

    } else {
        request.setAttribute("error", true);
        request.setAttribute("errorMsg", IdentityManagementEndpointUtil.i18n(recoveryResourceBundle,
                "Password.cannot.be.empty"));
        request.setAttribute(IdentityManagementEndpointConstants.TENANT_DOMAIN, tenantDomain);
        request.setAttribute(IdentityManagementEndpointConstants.CALLBACK, callback);
        request.getRequestDispatcher("password-reset.jsp").forward(request, response);
        return;
    }

    session.invalidate();
%>

<%!
    Map<String, String> extractQueryParamsFromURL(String url) {
        String queryParams = url.substring(url.indexOf("?") + 1);
        String[] parameterList = queryParams.split("&");
        Map<String, String> queryMap = new HashMap<>();
        for (String param : parameterList) {
            if (param.contains("=")) {
                String key = param.substring(0, param.indexOf("="));
                String value = param.substring(param.indexOf("=") + 1);
                queryMap.put(key, value);
            }
        }
        return queryMap;
    }
%>

<%@ page contentType="text/html;charset=UTF-8" language="java" %>

<!doctype html>
<html>
<head>
    <%
        File headerFile = new File(getServletContext().getRealPath("extensions/header.jsp"));
        if (headerFile.exists()) {
    %>
    <jsp:include page="extensions/header.jsp"/>
    <% } else { %>
    <jsp:include page="includes/header.jsp"/>
    <% } %>
</head>
<body>

    <form id="callbackForm" name="callbackForm" method="post" action="/commonauth">
        <%
            if (username != null) {
        %>
        <div>
            <input type="hidden" name="username"
                   value="<%=Encode.forHtmlAttribute(username)%>"/>
        </div>
        <%
            }
        %>
        <%
            if (sessionDataKey != null) {
        %>
        <div>
            <input type="hidden" name="sessionDataKey"
                   value="<%=Encode.forHtmlAttribute(sessionDataKey)%>"/>
        </div>
        <%
            }
        %>
    </form>

    <!-- footer -->
    <%
        File footerFile = new File(getServletContext().getRealPath("extensions/footer.jsp"));
        if (footerFile.exists()) {
    %>
    <jsp:include page="extensions/footer.jsp"/>
    <% } else { %>
    <jsp:include page="includes/footer.jsp"/>
    <% } %>

    <script type="application/javascript">
        $(document).ready(function () {

            <%
                try {
                    if(isAutoLoginEnable) {
            %>
                    <%
                        if (sessionDataKey != null) {
                    %>
                            document.callbackForm.submit();
                    <%
                        } else {
                    %>
                            location.href = "<%= IdentityManagementEndpointUtil.encodeURL(callback)%>";
                    <%
                        }
                    } else {
                        Map<String, String> queryMap = extractQueryParamsFromURL(callback);
                        queryMap.put("passwordReset", "true");
                        String parameterizedCallback = FrameworkUtils.buildURLWithQueryParams(callback, queryMap);
                    %>
                    location.href = "<%= IdentityManagementEndpointUtil.getURLEncodedCallback(parameterizedCallback)%>";
                    <%
                    }
                    } catch (URISyntaxException e) {
                        request.setAttribute("error", true);
                        request.setAttribute("errorMsg", "Invalid callback URL found in the request.");
                        request.getRequestDispatcher("error.jsp").forward(request, response);
                        return;
                    }
            %>

        });
    </script>
</body>
</html>

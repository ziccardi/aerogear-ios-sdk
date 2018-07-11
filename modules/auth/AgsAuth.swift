import AGSCore
import Foundation

/**
 AeroGear Services Auth SDK

 Allows users to perform login/logout actions against an Keycloak service provisioned by the AeroGear mobile service on OpenShift.

 ### Example ###
  *initialise the authentication configuration service and configure the Auth SDK*
 ````
 let authConfig = AuthenticationConfig(redirectURL: "com.youapp://callback")
 AgsAuth.instance.configure(authConfig: authConfig)
````

 *Login using the configured Auth SDK*
````
 AgsAuth.instance.login()
 ````
 */
open class AgsAuth {
    private static let serviceId = "keycloak"

    /** instance of the Auth SDK */
    public static let instance = AgsAuth(AgsCore.instance.getConfiguration(serviceId))

    /** Errors generated by the auth module */
    public enum Errors: Error {
        /** Thrown when trying to use auth before executing configure method */
        case serviceNotConfigured
        /** Thrown when Auth config is missing in mobile-services.json */
        case noServiceConfigurationFound
        /** Thrown when no user is logged in */
        case noLoggedInUserError
        /** Thrown when no idenity token */
        case noIdentityTokenError
    }

    private let credentialManager: CredentialsManager
    private var jwksManager: JwksManager?
    private var authenticator: Authenticator?

    private let serviceConfig: MobileService?
    private var keycloakConfig: KeycloakConfig?

    private var configured: Bool {
        return keycloakConfig != nil
    }

    /**
     Initialise the auth SDK

     - parameters:
         - mobileConfig: the configuration for the auth service from the service definition file
     */
    init(_ mobileConfig: MobileService?) {
        self.serviceConfig = mobileConfig
        credentialManager = CredentialsManager()
    }

    /**
     Configure the Auth SDK.

     - important: This function should be called before any other functions are invoked. Only need to call this once.

     - parameters:
         - authConfig: Configuration options for the auth module

     - throws: a `noServiceConfigurationFound` error if no authentication configuration
        was found in the `mobileConfig` used to initialise the Auth SDK
     */
    public func configure(authConfig: AuthenticationConfig) throws {
        if let config = serviceConfig {
            jwksManager = JwksManager(AgsCore.instance.getHttp(), authConfig)
            guard configured else {
                keycloakConfig = KeycloakConfig(config, authConfig)
                authenticator = OIDCAuthenticator(http: AgsCore.instance.getHttp(), keycloakConfig: keycloakConfig!, authConfig: authConfig, credentialManager: credentialManager)
                return
            }
            AgsCore.logger.warning("Auth SDK configure method called more than once.")
        } else {
            throw Errors.noServiceConfigurationFound
        }
    }

    /**
     Perform user login action.

     - parameters:
        - presentingViewController: the ViewController that initiates the login process
        - onCompleted: callback function that will be invoked when the login is finished
        - user: the user returned in the `onCompleted` callback function.  Will be nil if login failed
        - error: the error returned in the `onCompleted` callback function. Will be nil if login was successful
     - throws: a `serviceNotConfigured` error if the Auth SDK has not been configured
     */
    public func login(presentingViewController: UIViewController, onCompleted: @escaping (_ user: User?, _ error: Error?) -> Void) throws {
        guard configured, let authenticator = authenticator else {
            throw Errors.serviceNotConfigured
        }
        authenticator.authenticate(presentingViewController: presentingViewController, onCompleted: onCompleted)
    }

    /**
     Resume the authentication process.

     This function should be invoked when the user has finished logging in via the browser and redirected back to the app that started the login.

     - parameters:
         - url: The redirect url passed backed from the login process

     - throws: a `serviceNotConfigured` error if the Auth SDK has not been configured

     - returns: true if the login process can be resumed, false otherwise
     */
    public func resumeAuth(url: URL) throws -> Bool {
        guard configured, let authenticator = authenticator else {
            throw Errors.serviceNotConfigured
        }
        return authenticator.resumeAuth(url: url)
    }

    /**
     Perform the logout action.

     - parameters:
        - onCompleted: callback function that will be invoked when the logout process has completed
        - error: the `serviceNotConfigured` error returned in the `onCompleted` callback function

     - throws: a `serviceNotConfigured` error if the Auth SDK has not been configured or
        a `noLoggedInUserError` if no user is logged in
     */
    public func logout(onCompleted: @escaping (_ error: Error?) -> Void) throws {
        guard configured, let authenticator = authenticator else {
            throw Errors.serviceNotConfigured
        }
        do {
            if let currentUser = try currentUser() {
                authenticator.logout(currentUser: currentUser, onCompleted: onCompleted)
                return
            }
        }
        onCompleted(Errors.noLoggedInUserError);
    }

    /**
     Get the current logged in user.

     - throws:  a `serviceNotConfigured` error if the Auth SDK has not been configured

     - returns: the user that is currently logged in
     */
    public func currentUser() throws -> User? {
        var user: User?

        guard configured else {
            throw Errors.serviceNotConfigured
        }

        guard let currentCredential = credentialManager.load() else {
            return nil
        }

        guard let jwks = jwksManager?.load(keycloakConfig!) else {
            return nil
        }

        guard let jwt = currentCredential.accessToken else {
            return nil
        }

        let valid = try Jwt.verifyJwt(jwks: jwks, jwt: jwt)

        if !currentCredential.isExpired && valid && currentCredential.isAuthorized {
            user = User(credential: currentCredential, clientName: keycloakConfig!.clientID)
        }
        return user
    }
}

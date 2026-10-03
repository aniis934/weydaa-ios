// GÉNÉRÉ par scripts/convert-strings.mjs — NE PAS MODIFIER À LA MAIN.
// Source : strings.xml de l'app Android (fr / ar / en) + scripts/ios-strings.json.
// swiftlint:disable all

import Foundation

nonisolated enum L10n {
    /// Mes données
    static var accountDataTitle: String { tr("account_data_title") }
    /// Confirmer avec Google et supprimer
    static var accountDeleteGoogleConfirm: String { tr("account_delete_google_confirm") }
    /// Votre compte est lié à Google : confirmez votre identité avec Google pour le supprimer.
    static var accountDeleteGoogleHint: String { tr("account_delete_google_hint") }
    /// Créer une alerte
    static var alertCreate: String { tr("alert_create") }
    /// Alerte créée : vous serez prévenu des nouvelles annonces.
    static var alertCreated: String { tr("alert_created") }
    /// Supprimer l'alerte
    static var alertDelete: String { tr("alert_delete") }
    /// Cette alerte existe déjà.
    static var alertDuplicate: String { tr("alert_duplicate") }
    /// Limite de 5 alertes atteinte — supprimez-en une.
    static var alertLimit: String { tr("alert_limit") }
    /// Créée le %1$s
    static func alertsCreatedOn(_ p1: String) -> String { tr("alerts_created_on", p1) }
    /// Aucune alerte
    static var alertsEmpty: String { tr("alerts_empty") }
    /// Créez une alerte depuis une recherche filtrée pour être prévenu des nouvelles annonces.
    static var alertsEmptyHint: String { tr("alerts_empty_hint") }
    /// Mes alertes
    static var alertsTitle: String { tr("alerts_title") }
    /// Toutes
    static var allCategories: String { tr("all_categories") }
    /// Weydaa
    static var appName: String { tr("app_name") }
    /// Non
    static var attrNo: String { tr("attr_no") }
    /// Oui
    static var attrYes: String { tr("attr_yes") }
    /// Continuer
    static var authContinue: String { tr("auth_continue") }
    /// Email
    static var authEmail: String { tr("auth_email") }
    /// Indiquez votre email : si un compte existe, vous recevrez un lien de réinitialisation.
    static var authForgotBody: String { tr("auth_forgot_body") }
    /// Envoyer le lien
    static var authForgotButton: String { tr("auth_forgot_button") }
    /// Mot de passe oublié ?
    static var authForgotLink: String { tr("auth_forgot_link") }
    /// Si un compte existe pour %1$s, un lien de réinitialisation vient d'être envoyé. Pensez à vérifier vos spams.
    static func authForgotSentBody(_ p1: String) -> String { tr("auth_forgot_sent_body", p1) }
    /// Email envoyé
    static var authForgotSentTitle: String { tr("auth_forgot_sent_title") }
    /// Mot de passe oublié
    static var authForgotTitle: String { tr("auth_forgot_title") }
    /// Continuer avec Google
    static var authGoogleButton: String { tr("auth_google_button") }
    /// Déjà un compte ?
    static var authHaveAccount: String { tr("auth_have_account") }
    /// Se connecter
    static var authLoginButton: String { tr("auth_login_button") }
    /// Se connecter
    static var authLoginLink: String { tr("auth_login_link") }
    /// Ravi de vous revoir sur Weydaa.
    static var authLoginSubtitle: String { tr("auth_login_subtitle") }
    /// Connexion
    static var authLoginTitle: String { tr("auth_login_title") }
    /// Nom complet
    static var authName: String { tr("auth_name") }
    /// Pas encore de compte ?
    static var authNoAccount: String { tr("auth_no_account") }
    /// ou
    static var authOr: String { tr("auth_or") }
    /// Mot de passe
    static var authPassword: String { tr("auth_password") }
    /// Masquer
    static var authPasswordHide: String { tr("auth_password_hide") }
    /// 8 caractères min., une majuscule et un chiffre
    static var authPasswordRules: String { tr("auth_password_rules") }
    /// Afficher
    static var authPasswordShow: String { tr("auth_password_show") }
    /// Téléphone (optionnel)
    static var authPhoneOptional: String { tr("auth_phone_optional") }
    /// politique de confidentialité
    static var authPrivacyLink: String { tr("auth_privacy_link") }
    /// Créer mon compte
    static var authRegisterButton: String { tr("auth_register_button") }
    /// Créer un compte
    static var authRegisterLink: String { tr("auth_register_link") }
    /// Rejoignez la marketplace algérienne.
    static var authRegisterSubtitle: String { tr("auth_register_subtitle") }
    /// Inscription
    static var authRegisterTitle: String { tr("auth_register_title") }
    /// Réessayez dans %1$d min.
    static func authRetryIn(_ p1: Int) -> String { tr("auth_retry_in", p1) }
    /// conditions d'utilisation
    static var authTermsLink: String { tr("auth_terms_link") }
    /// En continuant, vous acceptez les %1$s et la %2$s de Weydaa.
    static func authTermsNotice(_ p1: String, _ p2: String) -> String { tr("auth_terms_notice", p1, p2) }
    /// %d essais restants.
    static func authVerifyAttemptsLeft(_ p1: Int) -> String { tr("auth_verify_attempts_left", p1) }
    /// Nous avons envoyé un code à 6 chiffres à %1$s. Saisissez-le pour activer votre compte.
    static func authVerifyBody(_ p1: String) -> String { tr("auth_verify_body", p1) }
    /// Vérifier
    static var authVerifyButton: String { tr("auth_verify_button") }
    /// Code à 6 chiffres
    static var authVerifyCode: String { tr("auth_verify_code") }
    /// Plus tard
    static var authVerifyLater: String { tr("auth_verify_later") }
    /// Renvoyer le code
    static var authVerifyResend: String { tr("auth_verify_resend") }
    /// Renvoyer dans %1$d s
    static func authVerifyResendIn(_ p1: Int) -> String { tr("auth_verify_resend_in", p1) }
    /// Nouveau code envoyé.
    static var authVerifyResent: String { tr("auth_verify_resent") }
    /// Email vérifié !
    static var authVerifySuccess: String { tr("auth_verify_success") }
    /// Votre compte est activé : vous pouvez déposer des annonces et contacter les vendeurs.
    static var authVerifySuccessBody: String { tr("auth_verify_success_body") }
    /// Vérifiez votre email
    static var authVerifyTitle: String { tr("auth_verify_title") }
    /// Retour
    static var back: String { tr("back") }
    /// Annuler
    static var cancel: String { tr("cancel") }
    /// Toutes les catégories
    static var categoriesAllRow: String { tr("categories_all_row") }
    /// Aucune catégorie ne correspond
    static var categoriesEmpty: String { tr("categories_empty") }
    /// Rechercher une catégorie
    static var categoriesSearchHint: String { tr("categories_search_hint") }
    /// Toutes
    static var categoryAllTile: String { tr("category_all_tile") }
    /// Après le changement, vous serez déconnecté de tous vos appareils.
    static var changePasswordBody: String { tr("change_password_body") }
    /// Confirmer le nouveau mot de passe
    static var changePasswordConfirm: String { tr("change_password_confirm") }
    /// Mot de passe actuel
    static var changePasswordCurrent: String { tr("change_password_current") }
    /// Les deux mots de passe ne correspondent pas.
    static var changePasswordMismatch: String { tr("change_password_mismatch") }
    /// Nouveau mot de passe
    static var changePasswordNew: String { tr("change_password_new") }
    /// Mettre à jour
    static var changePasswordSubmit: String { tr("change_password_submit") }
    /// Changer le mot de passe
    static var changePasswordTitle: String { tr("change_password_title") }
    /// Archiver
    static var chatArchive: String { tr("chat_archive") }
    /// Conversation archivée
    static var chatArchived: String { tr("chat_archived") }
    /// Vous ne recevrez plus ses messages et il ne pourra plus vous contacter.
    static var chatBlockConfirmBody: String { tr("chat_block_confirm_body") }
    /// Bloquer cet utilisateur
    static var chatBlockUser: String { tr("chat_block_user") }
    /// Utilisateur bloqué
    static var chatBlockedDone: String { tr("chat_blocked_done") }
    /// Supprimer
    static var chatDelete: String { tr("chat_delete") }
    /// Le message sera masqué pour les deux participants.
    static var chatDeleteConfirmBody: String { tr("chat_delete_confirm_body") }
    /// Supprimer le message
    static var chatDeleteMessage: String { tr("chat_delete_message") }
    /// Compte supprimé
    static var chatDeletedUser: String { tr("chat_deleted_user") }
    /// Délai de suppression dépassé (5 min).
    static var chatDeletionWindowExpired: String { tr("chat_deletion_window_expired") }
    /// Vous : %1$s
    static func chatLastMessageYou(_ p1: String) -> String { tr("chat_last_message_you", p1) }
    /// Message supprimé
    static var chatMessageDeleted: String { tr("chat_message_deleted") }
    /// Votre message…
    static var chatMessagePlaceholder: String { tr("chat_message_placeholder") }
    /// Plus d'actions
    static var chatMoreActions: String { tr("chat_more_actions") }
    /// Aucune conversation archivée
    static var chatNoArchives: String { tr("chat_no_archives") }
    /// Aucune conversation
    static var chatNoConversations: String { tr("chat_no_conversations") }
    /// Contactez un vendeur depuis une annonce pour démarrer une conversation.
    static var chatNoConversationsDesc: String { tr("chat_no_conversations_desc") }
    /// En ligne
    static var chatOnline: String { tr("chat_online") }
    /// Lu
    static var chatRead: String { tr("chat_read") }
    /// Aucune conversation ne correspond.
    static var chatSearchEmpty: String { tr("chat_search_empty") }
    /// Rechercher une conversation…
    static var chatSearchPlaceholder: String { tr("chat_search_placeholder") }
    /// Envoyer
    static var chatSend: String { tr("chat_send") }
    /// Envoyez un message pour contacter %1$s.
    static func chatSendMessageTo(_ p1: String) -> String { tr("chat_send_message_to", p1) }
    /// Démarrez la conversation
    static var chatStartConversation: String { tr("chat_start_conversation") }
    /// Archives
    static var chatTabArchives: String { tr("chat_tab_archives") }
    /// Conversations
    static var chatTabConversations: String { tr("chat_tab_conversations") }
    /// En train d'écrire…
    static var chatTyping: String { tr("chat_typing") }
    /// Désarchiver
    static var chatUnarchive: String { tr("chat_unarchive") }
    /// Conversation désarchivée
    static var chatUnarchived: String { tr("chat_unarchived") }
    /// Débloquer cet utilisateur
    static var chatUnblockUser: String { tr("chat_unblock_user") }
    /// Utilisateur débloqué
    static var chatUnblockedDone: String { tr("chat_unblocked_done") }
    /// Non lu
    static var chatUnread: String { tr("chat_unread") }
    /// Voir l'annonce
    static var chatViewListing: String { tr("chat_view_listing") }
    /// Fermer
    static var close: String { tr("close") }
    /// Email
    static var contactEmail: String { tr("contact_email") }
    /// Une question, un problème avec une annonce ou votre compte ? Écrivez-nous, nous répondons par email.
    static var contactIntro: String { tr("contact_intro") }
    /// Message
    static var contactMessage: String { tr("contact_message") }
    /// Message envoyé
    static var contactMessageSent: String { tr("contact_message_sent") }
    /// Nom
    static var contactName: String { tr("contact_name") }
    /// Envoyer
    static var contactSend: String { tr("contact_send") }
    /// Envoyer un message
    static var contactSendMessage: String { tr("contact_send_message") }
    /// Merci ! Nous vous répondrons par email dans les meilleurs délais.
    static var contactSentBody: String { tr("contact_sent_body") }
    /// Message envoyé
    static var contactSentTitle: String { tr("contact_sent_title") }
    /// Sujet
    static var contactSubject: String { tr("contact_subject") }
    /// Bonjour, est-ce encore disponible ?
    static var contactTemplate1: String { tr("contact_template_1") }
    /// Quel est votre prix final ?
    static var contactTemplate2: String { tr("contact_template_2") }
    /// Je suis intéressé(e).
    static var contactTemplate3: String { tr("contact_template_3") }
    /// Nous contacter
    static var contactTitle: String { tr("contact_title") }
    /// À %1$s
    static func contactToSeller(_ p1: String) -> String { tr("contact_to_seller", p1) }
    /// DA
    static var currencyDa: String { tr("currency_da") }
    /// Supprimer définitivement
    static var deleteAccountAction: String { tr("delete_account_action") }
    /// Votre compte est anonymisé, vos annonces quittent le site et vos données personnelles sont effacées. Cette action est définitive.
    static var deleteAccountBody: String { tr("delete_account_body") }
    /// Action irréversible. Exportez vos données avant si vous le souhaitez.
    static var deleteAccountConfirmBody: String { tr("delete_account_confirm_body") }
    /// Supprimer le compte ?
    static var deleteAccountConfirmTitle: String { tr("delete_account_confirm_title") }
    /// Votre mot de passe
    static var deleteAccountPassword: String { tr("delete_account_password") }
    /// Supprimer mon compte
    static var deleteAccountTitle: String { tr("delete_account_title") }
    /// Contacter le vendeur
    static var detailContact: String { tr("detail_contact") }
    /// Description
    static var detailDescription: String { tr("detail_description") }
    /// Expire le %1$s
    static func detailExpiresOn(_ p1: String) -> String { tr("detail_expires_on", p1) }
    /// Elle a peut-être été vendue, retirée par son auteur ou supprimée.
    static var detailNotFoundMessage: String { tr("detail_not_found_message") }
    /// Cette annonce n'est plus disponible
    static var detailNotFoundTitle: String { tr("detail_not_found_title") }
    /// Agrandir les photos
    static var detailOpenGallery: String { tr("detail_open_gallery") }
    /// Photo %1$d sur %2$d
    static func detailPhotoCounter(_ p1: Int, _ p2: Int) -> String { tr("detail_photo_counter", p1, p2) }
    /// Publiée %1$s
    static func detailPosted(_ p1: String) -> String { tr("detail_posted", p1) }
    /// Référence %1$s
    static func detailReference(_ p1: String) -> String { tr("detail_reference", p1) }
    /// • %1$s
    static func detailSafetyBullet(_ p1: String) -> String { tr("detail_safety_bullet", p1) }
    /// Privilégiez les échanges en personne dans un lieu public
    static var detailSafetyTip1: String { tr("detail_safety_tip1") }
    /// Ne payez jamais à l'avance ni par virement
    static var detailSafetyTip2: String { tr("detail_safety_tip2") }
    /// Vérifiez l'article avant tout achat
    static var detailSafetyTip3: String { tr("detail_safety_tip3") }
    /// Attention aux prix anormalement bas
    static var detailSafetyTip4: String { tr("detail_safety_tip4") }
    /// Conseils de sécurité
    static var detailSafetyTitle: String { tr("detail_safety_title") }
    /// Vendeur
    static var detailSeller: String { tr("detail_seller") }
    /// Afficher le numéro
    static var detailShowPhone: String { tr("detail_show_phone") }
    /// Annonces similaires
    static var detailSimilar: String { tr("detail_similar") }
    /// Annonce expirée
    static var detailStatusExpired: String { tr("detail_status_expired") }
    /// Cette annonce n'est plus en ligne. Vous pouvez la modifier et la republier.
    static var detailStatusExpiredDesc: String { tr("detail_status_expired_desc") }
    /// En cours de validation
    static var detailStatusPending: String { tr("detail_status_pending") }
    /// Votre annonce sera visible dès validation par notre équipe.
    static var detailStatusPendingDesc: String { tr("detail_status_pending_desc") }
    /// Annonce rejetée ou supprimée
    static var detailStatusRejected: String { tr("detail_status_rejected") }
    /// Cette annonce n'est plus visible publiquement.
    static var detailStatusRejectedDesc: String { tr("detail_status_rejected_desc") }
    /// Article vendu
    static var detailStatusSold: String { tr("detail_status_sold") }
    /// Cet article a été vendu.
    static var detailStatusSoldDesc: String { tr("detail_status_sold_desc") }
    /// %1$d vues
    static func detailViews(_ p1: Int) -> String { tr("detail_views", p1) }
    /// Bio (optionnel)
    static var editProfileBio: String { tr("edit_profile_bio") }
    /// Un nouveau code de vérification sera envoyé à cette adresse.
    static var editProfileEmailChangeNote: String { tr("edit_profile_email_change_note") }
    /// Enregistrer
    static var editProfileSave: String { tr("edit_profile_save") }
    /// Modifier mon profil
    static var editProfileTitle: String { tr("edit_profile_title") }
    /// Aucune annonce trouvée
    static var emptyResults: String { tr("empty_results") }
    /// Élargissez votre recherche ou retirez un filtre.
    static var emptyResultsHint: String { tr("empty_results_hint") }
    /// Compte temporairement verrouillé. Réessayez dans quelques minutes.
    static var errorAccountLocked: String { tr("error_account_locked") }
    /// Ce compte est suspendu.
    static var errorAccountSuspended: String { tr("error_account_suspended") }
    /// Un compte administrateur ne peut pas être supprimé depuis l'application.
    static var errorAdminCannotDelete: String { tr("error_admin_cannot_delete") }
    /// Cette annonce est déjà dans vos favoris.
    static var errorAlreadyFavorited: String { tr("error_already_favorited") }
    /// Vous avez déjà signalé cette annonce
    static var errorAlreadyReported: String { tr("error_already_reported") }
    /// Cette annonce n'est plus disponible — les offres sont fermées.
    static var errorAnnonceUnavailable: String { tr("error_annonce_unavailable") }
    /// Vous ne pouvez pas vous bloquer vous-même.
    static var errorCannotBlockSelf: String { tr("error_cannot_block_self") }
    /// Vous ne pouvez pas vous contacter vous-même.
    static var errorCannotContactSelf: String { tr("error_cannot_contact_self") }
    /// Vous ne pouvez pas vous signaler vous-même.
    static var errorCannotReportSelf: String { tr("error_cannot_report_self") }
    /// Vous ne pouvez pas répondre à votre propre offre.
    static var errorCannotRespondOwnOffer: String { tr("error_cannot_respond_own_offer") }
    /// Catégorie introuvable. Choisissez-en une autre.
    static var errorCategoryNotFound: String { tr("error_category_not_found") }
    /// Un code vient d'être envoyé. Patientez une minute avant d'en redemander un.
    static var errorCodeCooldown: String { tr("error_code_cooldown") }
    /// Code expiré. Demandez-en un nouveau.
    static var errorCodeExpired: String { tr("error_code_expired") }
    /// Limite quotidienne d'envois atteinte. Réessayez demain.
    static var errorDailyLimit: String { tr("error_daily_limit") }
    /// Votre email a changé : demandez un nouveau code.
    static var errorEmailChanged: String { tr("error_email_changed") }
    /// Cet email est déjà utilisé.
    static var errorEmailExists: String { tr("error_email_exists") }
    /// Vérifiez votre email pour continuer.
    static var errorEmailNotVerified: String { tr("error_email_not_verified") }
    /// L'email n'a pas pu être envoyé. Réessayez.
    static var errorEmailSendFailed: String { tr("error_email_send_failed") }
    /// Action non autorisée.
    static var errorForbidden: String { tr("error_forbidden") }
    /// Impossible de charger les annonces. Vérifiez votre connexion.
    static var errorGeneric: String { tr("error_generic") }
    /// Votre compte Google ne fournit pas d'email vérifié.
    static var errorGoogleEmailMissing: String { tr("error_google_email_missing") }
    /// Aucun compte Google sur cet appareil. Ajoutez-en un dans les paramètres Android.
    static var errorGoogleNoAccount: String { tr("error_google_no_account") }
    /// Ce compte Google ne correspond pas au compte connecté.
    static var errorGoogleReauthMismatch: String { tr("error_google_reauth_mismatch") }
    /// Connexion Google impossible. Réessayez.
    static var errorGoogleSignIn: String { tr("error_google_sign_in") }
    /// Services Google indisponibles sur cet appareil.
    static var errorGoogleUnavailable: String { tr("error_google_unavailable") }
    /// Code incorrect.
    static var errorIncorrectCode: String { tr("error_incorrect_code") }
    /// Mot de passe actuel incorrect.
    static var errorIncorrectPassword: String { tr("error_incorrect_password") }
    /// Certaines caractéristiques sont invalides. Vérifiez les champs signalés.
    static var errorInvalidAttributes: String { tr("error_invalid_attributes") }
    /// Email ou mot de passe incorrect.
    static var errorInvalidCredentials: String { tr("error_invalid_credentials") }
    /// Données invalides. Vérifiez les champs.
    static var errorInvalidData: String { tr("error_invalid_data") }
    /// Connexion Google refusée : jeton invalide ou expiré. Réessayez.
    static var errorInvalidGoogleToken: String { tr("error_invalid_google_token") }
    /// Nombre maximal de photos dépassé.
    static var errorMaxImages: String { tr("error_max_images") }
    /// Aucune application de cet appareil ne peut effectuer cette action.
    static var errorNoApp: String { tr("error_no_app") }
    /// Aucun code en attente. Demandez-en un nouveau.
    static var errorNoCodePending: String { tr("error_no_code_pending") }
    /// Aucune offre en attente.
    static var errorNoOpenOffer: String { tr("error_no_open_offer") }
    /// Aucun numéro n'est renseigné pour cette annonce.
    static var errorNoPhone: String { tr("error_no_phone") }
    /// Introuvable.
    static var errorNotFound: String { tr("error_not_found") }
    /// Cette annonce ne peut pas encore être renouvelée (moins de 7 jours avant expiration).
    static var errorNotRenewable: String { tr("error_not_renewable") }
    /// Une offre est déjà en attente de réponse.
    static var errorOfferAlreadyOpen: String { tr("error_offer_already_open") }
    /// Les offres ne sont pas possibles sur une annonce gratuite.
    static var errorOfferNotAllowed: String { tr("error_offer_not_allowed") }
    /// Pas de connexion. Vérifiez votre réseau et réessayez.
    static var errorOffline: String { tr("error_offline") }
    /// Vous ne pouvez pas vous noter vous-même
    static var errorOwnReview: String { tr("error_own_review") }
    /// Action impossible pour un compte connecté via Google.
    static var errorPasswordChangeNotAllowed: String { tr("error_password_change_not_allowed") }
    /// Impossible de lire cette image.
    static var errorPhotoRead: String { tr("error_photo_read") }
    /// Limite atteinte : vous avez publié trop d'annonces aujourd'hui.
    static var errorPostRateLimited: String { tr("error_post_rate_limited") }
    /// Trop de tentatives. Réessayez plus tard.
    static var errorRateLimited: String { tr("error_rate_limited") }
    /// Limite de renouvellement atteinte (3).
    static var errorRenewalLimit: String { tr("error_renewal_limit") }
    /// Vous devez avoir contacté ce vendeur pour le noter
    static var errorReviewNotEligible: String { tr("error_review_not_eligible") }
    /// Ajoutez un mot-clé ou un filtre avant de créer une alerte.
    static var errorSavedSearchEmpty: String { tr("error_saved_search_empty") }
    /// Erreur serveur. Réessayez dans un instant.
    static var errorServer: String { tr("error_server") }
    /// Session expirée, veuillez vous reconnecter.
    static var errorSessionExpired: String { tr("error_session_expired") }
    /// Chargement impossible
    static var errorTitle: String { tr("error_title") }
    /// Format non supporté. Utilisez JPEG, PNG, WebP ou GIF.
    static var errorUploadBadFormat: String { tr("error_upload_bad_format") }
    /// L'image n'a pas pu être envoyée. Réessayez.
    static var errorUploadFailed: String { tr("error_upload_failed") }
    /// L'image dépasse la taille maximale de 5 Mo.
    static var errorUploadTooLarge: String { tr("error_upload_too_large") }
    /// Cet utilisateur vous a bloqué ou est bloqué.
    static var errorUserBlocked: String { tr("error_user_blocked") }
    /// Ce compte a été supprimé.
    static var errorUserDeleted: String { tr("error_user_deleted") }
    /// Compte introuvable.
    static var errorUserNotFound: String { tr("error_user_not_found") }
    /// Préparer le fichier
    static var exportAction: String { tr("export_action") }
    /// Un fichier JSON rassemble votre profil, vos annonces, vos messages, vos favoris, vos avis et vos notifications. Deux exports par 24 heures.
    static var exportBody: String { tr("export_body") }
    /// Export prêt à partager
    static var exportReady: String { tr("export_ready") }
    /// Exporter mes données
    static var exportTitle: String { tr("export_title") }
    /// Ajouter aux favoris
    static var favoriteAdd: String { tr("favorite_add") }
    /// Retirer des favoris
    static var favoriteRemove: String { tr("favorite_remove") }
    /// Aucun favori pour l'instant
    static var favoritesEmpty: String { tr("favorites_empty") }
    /// Touchez le cœur d'une annonce pour la retrouver ici.
    static var favoritesEmptyHint: String { tr("favorites_empty_hint") }
    /// Mes favoris
    static var favoritesTitle: String { tr("favorites_title") }
    /// À la une
    static var featuredBadge: String { tr("featured_badge") }
    /// Toutes
    static var filterAll: String { tr("filter_all") }
    /// Tout
    static var filtersAll: String { tr("filters_all") }
    /// Toutes les communes
    static var filtersAllCommunes: String { tr("filters_all_communes") }
    /// Toutes les wilayas
    static var filtersAllWilayas: String { tr("filters_all_wilayas") }
    /// Voir les résultats
    static var filtersApply: String { tr("filters_apply") }
    /// %1$s ≤ %2$s
    static func filtersAttrMax(_ p1: String, _ p2: String) -> String { tr("filters_attr_max", p1, p2) }
    /// %1$s ≥ %2$s
    static func filtersAttrMin(_ p1: String, _ p2: String) -> String { tr("filters_attr_min", p1, p2) }
    /// %1$s : %2$s
    static func filtersAttrValue(_ p1: String, _ p2: String) -> String { tr("filters_attr_value", p1, p2) }
    /// Tout effacer
    static var filtersClearAll: String { tr("filters_clear_all") }
    /// À la une
    static var filtersFeaturedChip: String { tr("filters_featured_chip") }
    /// Annonces à la une seulement
    static var filtersFeaturedOnly: String { tr("filters_featured_only") }
    /// Localisation
    static var filtersLocation: String { tr("filters_location") }
    /// Prix
    static var filtersPrice: String { tr("filters_price") }
    /// %1$s – %2$s DA
    static func filtersPriceBetween(_ p1: String, _ p2: String) -> String { tr("filters_price_between", p1, p2) }
    /// ≥ %1$s DA
    static func filtersPriceFrom(_ p1: String) -> String { tr("filters_price_from", p1) }
    /// Max
    static var filtersPriceMax: String { tr("filters_price_max") }
    /// Min
    static var filtersPriceMin: String { tr("filters_price_min") }
    /// ≤ %1$s DA
    static func filtersPriceTo(_ p1: String) -> String { tr("filters_price_to", p1) }
    /// Max
    static var filtersRangeMax: String { tr("filters_range_max") }
    /// Min
    static var filtersRangeMin: String { tr("filters_range_min") }
    /// Retirer ce filtre
    static var filtersRemove: String { tr("filters_remove") }
    /// Réinitialiser
    static var filtersReset: String { tr("filters_reset") }
    /// Trier par
    static var filtersSort: String { tr("filters_sort") }
    /// Sous-catégories
    static var filtersSubcategories: String { tr("filters_subcategories") }
    /// Filtres
    static var filtersTitle: String { tr("filters_title") }
    /// Oui uniquement
    static var filtersYesOnly: String { tr("filters_yes_only") }
    /// Voir toutes les annonces
    static var homeBrowseAll: String { tr("home_browse_all") }
    /// Publiez votre annonce gratuitement en moins d'une minute.
    static var homeCtaSubtitle: String { tr("home_cta_subtitle") }
    /// Vous vendez quelque chose ?
    static var homeCtaTitle: String { tr("home_cta_title") }
    /// Pour vous
    static var homeForYou: String { tr("home_for_you") }
    /// D'après vos recherches
    static var homeForYouSubtitle: String { tr("home_for_you_subtitle") }
    /// Tendances
    static var homeTrending: String { tr("home_trending") }
    /// Les plus consultées cette semaine
    static var homeTrendingSubtitle: String { tr("home_trending_subtitle") }
    /// العربية
    static var languageAr: String { tr("language_ar") }
    /// English
    static var languageEn: String { tr("language_en") }
    /// Français
    static var languageFr: String { tr("language_fr") }
    /// Le changement est immédiat. Android retient ce choix pour Weydaa seulement.
    static var languageHint: String { tr("language_hint") }
    /// Sur cette version d'Android, la langue d'une application se règle depuis les paramètres du système.
    static var languageLegacyHint: String { tr("language_legacy_hint") }
    /// Ouvrir les paramètres
    static var languageOpenSettings: String { tr("language_open_settings") }
    /// Langue du système
    static var languageSystem: String { tr("language_system") }
    /// Langue de l'application
    static var languageTitle: String { tr("language_title") }
    /// À propos de Weydaa
    static var legalAbout: String { tr("legal_about") }
    /// Suppression de compte
    static var legalAccountDeletion: String { tr("legal_account_deletion") }
    /// Nous contacter
    static var legalContact: String { tr("legal_contact") }
    /// Mentions légales
    static var legalNotice: String { tr("legal_notice") }
    /// S'ouvre dans le navigateur
    static var legalOpensBrowser: String { tr("legal_opens_browser") }
    /// Politique de confidentialité
    static var legalPrivacy: String { tr("legal_privacy") }
    /// Conditions générales d'utilisation
    static var legalTerms: String { tr("legal_terms") }
    /// À propos et informations légales
    static var legalTitle: String { tr("legal_title") }
    /// Version %1$s
    static func legalVersion(_ p1: String) -> String { tr("legal_version", p1) }
    /// Chargement…
    static var loading: String { tr("loading") }
    /// Connectez-vous pour déposer une annonce, envoyer des messages et gérer votre profil.
    static var loginRequiredBody: String { tr("login_required_body") }
    /// Connectez-vous
    static var loginRequiredTitle: String { tr("login_required_title") }
    /// Membre depuis %1$s
    static func memberSince(_ p1: String) -> String { tr("member_since", p1) }
    /// Motif de la modération
    static var moderationReason: String { tr("moderation_reason") }
    /// Supprimer
    static var myListingDelete: String { tr("my_listing_delete") }
    /// Cette action est irréversible. L'annonce sera définitivement supprimée.
    static var myListingDeleteConfirmBody: String { tr("my_listing_delete_confirm_body") }
    /// Supprimer l'annonce ?
    static var myListingDeleteConfirmTitle: String { tr("my_listing_delete_confirm_title") }
    /// Annonce supprimée.
    static var myListingDeleted: String { tr("my_listing_deleted") }
    /// Modifier
    static var myListingEdit: String { tr("my_listing_edit") }
    /// Marquer vendu
    static var myListingMarkSold: String { tr("my_listing_mark_sold") }
    /// Renouveler 60 j (%1$d)
    static func myListingRenew(_ p1: Int) -> String { tr("my_listing_renew", p1) }
    /// Annonce renouvelée ! Active pour 60 jours.
    static var myListingRenewed: String { tr("my_listing_renewed") }
    /// L'annonce sera retirée des résultats de recherche et marquée comme vendue.
    static var myListingSoldConfirmBody: String { tr("my_listing_sold_confirm_body") }
    /// Confirmer la vente
    static var myListingSoldConfirmBtn: String { tr("my_listing_sold_confirm_btn") }
    /// Marquer comme vendu ?
    static var myListingSoldConfirmTitle: String { tr("my_listing_sold_confirm_title") }
    /// Annonce marquée vendue !
    static var myListingSoldDone: String { tr("my_listing_sold_done") }
    /// Mes annonces
    static var myListingsTitle: String { tr("my_listings_title") }
    /// Accueil
    static var navHome: String { tr("nav_home") }
    /// Annonces
    static var navListings: String { tr("nav_listings") }
    /// Messages
    static var navMessages: String { tr("nav_messages") }
    /// Déposer
    static var navPost: String { tr("nav_post") }
    /// Profil
    static var navProfile: String { tr("nav_profile") }
    /// Supprimer la notification
    static var notificationDelete: String { tr("notification_delete") }
    /// Annonce approuvée
    static var notificationTypeAnnonceApproved: String { tr("notification_type_annonce_approved") }
    /// Annonce expirée
    static var notificationTypeAnnonceExpired: String { tr("notification_type_annonce_expired") }
    /// Annonce rejetée
    static var notificationTypeAnnonceRejected: String { tr("notification_type_annonce_rejected") }
    /// Baisse de prix sur un favori
    static var notificationTypeFavoritePriceDrop: String { tr("notification_type_favorite_price_drop") }
    /// Favori vendu
    static var notificationTypeFavoriteSold: String { tr("notification_type_favorite_sold") }
    /// Nouveau message
    static var notificationTypeMessage: String { tr("notification_type_message") }
    /// Offre acceptée
    static var notificationTypeOfferAccepted: String { tr("notification_type_offer_accepted") }
    /// Contre-offre
    static var notificationTypeOfferCounter: String { tr("notification_type_offer_counter") }
    /// Nouvelle offre
    static var notificationTypeOfferReceived: String { tr("notification_type_offer_received") }
    /// Offre refusée
    static var notificationTypeOfferRejected: String { tr("notification_type_offer_rejected") }
    /// Nouvel avis
    static var notificationTypeReview: String { tr("notification_type_review") }
    /// Nouvelle annonce pour votre alerte
    static var notificationTypeSearchAlert: String { tr("notification_type_search_alert") }
    /// Aucune notification
    static var notificationsEmpty: String { tr("notifications_empty") }
    /// Tout marquer comme lu
    static var notificationsMarkAllRead: String { tr("notifications_mark_all_read") }
    /// Notifications
    static var notificationsTitle: String { tr("notifications_title") }
    /// Accepter
    static var offerAccept: String { tr("offer_accept") }
    /// Offre acceptée
    static var offerAccepted: String { tr("offer_accepted") }
    /// Une offre est déjà en cours pour cette annonce.
    static var offerAlreadyOpenNotice: String { tr("offer_already_open_notice") }
    /// Votre prix
    static var offerAmountPlaceholder: String { tr("offer_amount_placeholder") }
    /// Prix demandé
    static var offerAskingPrice: String { tr("offer_asking_price") }
    /// Contrer
    static var offerCounter: String { tr("offer_counter") }
    /// Contre-offre reçue
    static var offerCounterReceived: String { tr("offer_counter_received") }
    /// Contre-offre envoyée
    static var offerCounterSent: String { tr("offer_counter_sent") }
    /// Contre-proposition
    static var offerCounterTitle: String { tr("offer_counter_title") }
    /// Offre actuelle
    static var offerCurrent: String { tr("offer_current") }
    /// Refuser
    static var offerDecline: String { tr("offer_decline") }
    /// Offre refusée
    static var offerDeclined: String { tr("offer_declined") }
    /// Le vendeur pourra accepter, refuser ou faire une contre-proposition.
    static var offerHelper: String { tr("offer_helper") }
    /// Montant invalide.
    static var offerInvalidAmount: String { tr("offer_invalid_amount") }
    /// Faire une offre
    static var offerMake: String { tr("offer_make") }
    /// Offre reçue
    static var offerReceived: String { tr("offer_received") }
    /// Envoyer l'offre
    static var offerSend: String { tr("offer_send") }
    /// Offre envoyée
    static var offerSent: String { tr("offer_sent") }
    /// En attente de réponse…
    static var offerWaitingResponse: String { tr("offer_waiting_response") }
    /// Votre offre
    static var offerYourOffer: String { tr("offer_your_offer") }
    /// Pas de connexion internet
    static var offlineBanner: String { tr("offline_banner") }
    /// Description
    static var postAdDescription: String { tr("post_ad_description") }
    /// Décrivez votre article en détail : état, caractéristiques, raison de la vente…
    static var postAdDescriptionPlaceholder: String { tr("post_ad_description_placeholder") }
    /// Titre de l'annonce
    static var postAdTitle: String { tr("post_ad_title") }
    /// Ex : iPhone 14 Pro Max 256 Go
    static var postAdTitlePlaceholder: String { tr("post_ad_title_placeholder") }
    /// Analyse de votre annonce en cours…
    static var postAnalyzing: String { tr("post_analyzing") }
    /// Déposer une autre annonce
    static var postAnother: String { tr("post_another") }
    /// Retour
    static var postBack: String { tr("post_back") }
    /// %1$d / %2$d
    static func postCharCount(_ p1: Int, _ p2: Int) -> String { tr("post_char_count", p1, p2) }
    /// Choisissez une catégorie
    static var postChooseCategory: String { tr("post_choose_category") }
    /// Choisissez une sous-catégorie
    static var postChooseSubcategory: String { tr("post_choose_subcategory") }
    /// Aucun
    static var postClearSelection: String { tr("post_clear_selection") }
    /// Commune
    static var postCommune: String { tr("post_commune") }
    /// Abandonner
    static var postDiscardConfirm: String { tr("post_discard_confirm") }
    /// Continuer
    static var postDiscardKeep: String { tr("post_discard_keep") }
    /// Les changements apportés à cette annonce ne seront pas enregistrés.
    static var postDiscardMessage: String { tr("post_discard_message") }
    /// Abandonner les modifications ?
    static var postDiscardTitle: String { tr("post_discard_title") }
    /// Toute modification du titre ou de la description repassera votre annonce en vérification avant d'être de nouveau visible.
    static var postEditPendingWarning: String { tr("post_edit_pending_warning") }
    /// Modifier
    static var postEditStep: String { tr("post_edit_step") }
    /// Modifier l'annonce
    static var postEditTitle: String { tr("post_edit_title") }
    /// Votre annonce sera active pendant 60 jours. Vous pourrez la renouveler depuis « Mes annonces » avant son expiration.
    static var postExpirationNotice: String { tr("post_expiration_notice") }
    /// Indiquez où se trouve l'article pour rassurer les acheteurs (facultatif).
    static var postLocationHint: String { tr("post_location_hint") }
    /// Plus de détails (%1$d)
    static func postMoreDetails(_ p1: Int) -> String { tr("post_more_details", p1) }
    /// Mes annonces
    static var postMyListings: String { tr("post_my_listings") }
    /// Suivant
    static var postNext: String { tr("post_next") }
    /// Appareil photo
    static var postPhotoCamera: String { tr("post_photo_camera") }
    /// %1$d / %2$d photos
    static func postPhotoCount(_ p1: Int, _ p2: Int) -> String { tr("post_photo_count", p1, p2) }
    /// Galerie
    static var postPhotoGallery: String { tr("post_photo_gallery") }
    /// Principale
    static var postPhotoMain: String { tr("post_photo_main") }
    /// Définir comme photo principale
    static var postPhotoMakeMain: String { tr("post_photo_make_main") }
    /// Retirer la photo
    static var postPhotoRemove: String { tr("post_photo_remove") }
    /// Réessayer l'envoi
    static var postPhotoRetry: String { tr("post_photo_retry") }
    /// Retirez ou renvoyez les photos en erreur avant de continuer.
    static var postPhotosFailedHint: String { tr("post_photos_failed_hint") }
    /// Ajoutez jusqu'à %1$d photos (5 Mo max. chacune). La première sera la photo principale.
    static func postPhotosHint(_ p1: Int) -> String { tr("post_photos_hint", p1) }
    /// Vous ne pouvez pas ajouter plus de %1$d photos.
    static func postPhotosLimit(_ p1: Int) -> String { tr("post_photos_limit", p1) }
    /// Prix
    static var postPrice: String { tr("post_price") }
    /// Prix fixe
    static var postPriceFixed: String { tr("post_price_fixed") }
    /// Gratuit
    static var postPriceFree: String { tr("post_price_free") }
    /// Négociable
    static var postPriceNegotiable: String { tr("post_price_negotiable") }
    /// Prix indicatif — à débattre avec l'acheteur
    static var postPriceNegotiableHint: String { tr("post_price_negotiable_hint") }
    /// Prix non renseigné
    static var postPriceNotSet: String { tr("post_price_not_set") }
    /// Ex : 50 000
    static var postPricePlaceholder: String { tr("post_price_placeholder") }
    /// Type de prix
    static var postPriceType: String { tr("post_price_type") }
    /// Publier l'annonce
    static var postPublish: String { tr("post_publish") }
    /// Localisation non renseignée
    static var postReviewNoLocation: String { tr("post_review_no_location") }
    /// Aucune photo
    static var postReviewNoPhotos: String { tr("post_review_no_photos") }
    /// Numéro non affiché
    static var postReviewPhoneHidden: String { tr("post_review_phone_hidden") }
    /// Numéro affiché : %1$s
    static func postReviewPhoneShown(_ p1: String) -> String { tr("post_review_phone_shown", p1) }
    /// Assurez-vous que tout est correct avant de publier.
    static var postReviewSubtitle: String { tr("post_review_subtitle") }
    /// Vérifiez votre annonce
    static var postReviewTitle: String { tr("post_review_title") }
    /// Enregistrer
    static var postSave: String { tr("post_save") }
    /// Sélectionner une commune
    static var postSelectCommune: String { tr("post_select_commune") }
    /// Choisissez d'abord : %1$s
    static func postSelectParentFirst(_ p1: String) -> String { tr("post_select_parent_first", p1) }
    /// Sélectionner une wilaya
    static var postSelectWilaya: String { tr("post_select_wilaya") }
    /// Afficher mon numéro
    static var postShowPhone: String { tr("post_show_phone") }
    /// Visible par les acheteurs
    static var postShowPhoneHint: String { tr("post_show_phone_hint") }
    /// Caractéristiques
    static var postStepAttributes: String { tr("post_step_attributes") }
    /// Catégorie
    static var postStepCategory: String { tr("post_step_category") }
    /// Infos & prix
    static var postStepDetails: String { tr("post_step_details") }
    /// Localisation
    static var postStepLocation: String { tr("post_step_location") }
    /// Étape %1$d sur %2$d
    static func postStepOf(_ p1: Int, _ p2: Int) -> String { tr("post_step_of", p1, p2) }
    /// Photos
    static var postStepPhotos: String { tr("post_step_photos") }
    /// Vérification
    static var postStepReview: String { tr("post_step_review") }
    /// Votre annonce a été approuvée et est maintenant en ligne !
    static var postSuccessApproved: String { tr("post_success_approved") }
    /// Votre annonce est en cours de validation
    static var postSuccessDesc: String { tr("post_success_desc") }
    /// Votre annonce est en cours de vérification par un modérateur.
    static var postSuccessPendingReview: String { tr("post_success_pending_review") }
    /// Votre annonce a été publiée et sera examinée prochainement.
    static var postSuccessPublished: String { tr("post_success_published") }
    /// Annonce publiée !
    static var postSuccessTitle: String { tr("post_success_title") }
    /// Déposer une annonce
    static var postTitle: String { tr("post_title") }
    /// Vos modifications seront vérifiées avant d'être publiées.
    static var postUpdatedPending: String { tr("post_updated_pending") }
    /// Vos modifications sont enregistrées.
    static var postUpdatedSaved: String { tr("post_updated_saved") }
    /// Annonce mise à jour
    static var postUpdatedTitle: String { tr("post_updated_title") }
    /// Voir l'annonce
    static var postViewListing: String { tr("post_view_listing") }
    /// Wilaya
    static var postWilaya: String { tr("post_wilaya") }
    /// %1$s DA
    static func priceDzd(_ p1: String) -> String { tr("price_dzd", p1) }
    /// Gratuit
    static var priceFree: String { tr("price_free") }
    /// Négociable
    static var priceNegotiable: String { tr("price_negotiable") }
    /// Prix sur demande
    static var priceOnRequest: String { tr("price_on_request") }
    /// Mes données
    static var profileAccountData: String { tr("profile_account_data") }
    /// Mes alertes
    static var profileAlerts: String { tr("profile_alerts") }
    /// Changer le mot de passe
    static var profileChangePassword: String { tr("profile_change_password") }
    /// Modifier mon profil
    static var profileEdit: String { tr("profile_edit") }
    /// Mes favoris
    static var profileFavorites: String { tr("profile_favorites") }
    /// Langue
    static var profileLanguage: String { tr("profile_language") }
    /// Se déconnecter
    static var profileLogout: String { tr("profile_logout") }
    /// Vous devrez vous reconnecter pour gérer vos annonces et vos messages.
    static var profileLogoutConfirmBody: String { tr("profile_logout_confirm_body") }
    /// Se déconnecter ?
    static var profileLogoutConfirmTitle: String { tr("profile_logout_confirm_title") }
    /// Mes annonces
    static var profileMyListings: String { tr("profile_my_listings") }
    /// Vendeur recommandé
    static var profileRecommended: String { tr("profile_recommended") }
    /// Mon activité
    static var profileStatsTitle: String { tr("profile_stats_title") }
    /// Mon compte
    static var profileTitle: String { tr("profile_title") }
    /// Email non vérifié
    static var profileUnverified: String { tr("profile_unverified") }
    /// Email vérifié
    static var profileVerified: String { tr("profile_verified") }
    /// Vérifier
    static var profileVerifyAction: String { tr("profile_verify_action") }
    /// Vérifiez votre email pour déposer des annonces et contacter les vendeurs.
    static var profileVerifyBanner: String { tr("profile_verify_banner") }
    /// Compte
    static var pushChannelAccount: String { tr("push_channel_account") }
    /// Avis reçus et informations sur votre compte
    static var pushChannelAccountDesc: String { tr("push_channel_account_desc") }
    /// Annonces
    static var pushChannelListings: String { tr("push_channel_listings") }
    /// Validation, refus ou expiration de vos annonces, alertes de recherche
    static var pushChannelListingsDesc: String { tr("push_channel_listings_desc") }
    /// Messages
    static var pushChannelMessages: String { tr("push_channel_messages") }
    /// Nouveaux messages de vos conversations
    static var pushChannelMessagesDesc: String { tr("push_channel_messages_desc") }
    /// Offres
    static var pushChannelOffers: String { tr("push_channel_offers") }
    /// Offres reçues, acceptées, refusées ou contre-offres
    static var pushChannelOffersDesc: String { tr("push_channel_offers_desc") }
    /// %1$s sur 5
    static func ratingOutOfFive(_ p1: String) -> String { tr("rating_out_of_five", p1) }
    /// Signaler
    static var reportAction: String { tr("report_action") }
    /// Détails (optionnel)
    static var reportDetails: String { tr("report_details") }
    /// Précisez votre signalement…
    static var reportDetailsPlaceholder: String { tr("report_details_placeholder") }
    /// Raison
    static var reportReason: String { tr("report_reason") }
    /// Annonce en double
    static var reportReasonDuplicate: String { tr("report_reason_duplicate") }
    /// Arnaque / Fraude
    static var reportReasonFraud: String { tr("report_reason_fraud") }
    /// Contenu inapproprié
    static var reportReasonInappropriate: String { tr("report_reason_inappropriate") }
    /// Autre
    static var reportReasonOther: String { tr("report_reason_other") }
    /// Spam
    static var reportReasonSpam: String { tr("report_reason_spam") }
    /// Signalement envoyé, merci !
    static var reportSent: String { tr("report_sent") }
    /// Envoyer le signalement
    static var reportSubmit: String { tr("report_submit") }
    /// Signaler cette annonce
    static var reportTitle: String { tr("report_title") }
    /// Signaler cet utilisateur
    static var reportUserAction: String { tr("report_user_action") }
    /// Notre équipe de modération examinera son compte et ses échanges.
    static var reportUserHint: String { tr("report_user_hint") }
    /// Signaler cet utilisateur
    static var reportUserTitle: String { tr("report_user_title") }
    /// Confirmer le mot de passe
    static var resetConfirmPassword: String { tr("reset_confirm_password") }
    /// Ce lien de réinitialisation est invalide ou incomplet.
    static var resetInvalidLink: String { tr("reset_invalid_link") }
    /// Nouveau mot de passe
    static var resetNewPassword: String { tr("reset_new_password") }
    /// Réinitialiser le mot de passe
    static var resetSubmit: String { tr("reset_submit") }
    /// Choisissez un nouveau mot de passe sécurisé pour votre compte.
    static var resetSubtitle: String { tr("reset_subtitle") }
    /// Votre mot de passe a été réinitialisé avec succès. Vous pouvez maintenant vous connecter.
    static var resetSuccessBody: String { tr("reset_success_body") }
    /// Mot de passe modifié !
    static var resetSuccessTitle: String { tr("reset_success_title") }
    /// Nouveau mot de passe
    static var resetTitle: String { tr("reset_title") }
    /// %d annonces
    static func resultsCount(_ p1: Int) -> String { tr("results_count", p1) }
    /// Réessayer
    static var retry: String { tr("retry") }
    /// Utilisateur
    static var reviewAnonymous: String { tr("review_anonymous") }
    /// Commentaire (optionnel)
    static var reviewComment: String { tr("review_comment") }
    /// Décrivez votre expérience avec ce vendeur…
    static var reviewCommentPlaceholder: String { tr("review_comment_placeholder") }
    /// Modifier mon avis
    static var reviewEdit: String { tr("review_edit") }
    /// Laisser un avis
    static var reviewLeave: String { tr("review_leave") }
    /// Votre note
    static var reviewRating: String { tr("review_rating") }
    /// Publier
    static var reviewSend: String { tr("review_send") }
    /// Merci, votre avis est publié
    static var reviewSent: String { tr("review_sent") }
    /// %1$d étoiles sur 5
    static func reviewStar(_ p1: Int) -> String { tr("review_star", p1) }
    /// Aucun avis pour le moment
    static var reviewsEmpty: String { tr("reviews_empty") }
    /// Avis
    static var reviewsTitle: String { tr("reviews_title") }
    /// Effacer la recherche
    static var searchClear: String { tr("search_clear") }
    /// Effacer
    static var searchClearHistory: String { tr("search_clear_history") }
    /// Vouliez-vous dire %1$s ?
    static func searchDidYouMean(_ p1: String) -> String { tr("search_did_you_mean", p1) }
    /// Que cherchez-vous ?
    static var searchHint: String { tr("search_hint") }
    /// Recherches récentes
    static var searchHistory: String { tr("search_history") }
    /// Catégories
    static var sectionCategories: String { tr("section_categories") }
    /// À la une
    static var sectionFeatured: String { tr("section_featured") }
    /// Notre sélection du moment
    static var sectionFeaturedSubtitle: String { tr("section_featured_subtitle") }
    /// Villes populaires
    static var sectionPopularCities: String { tr("section_popular_cities") }
    /// Là où il y a le plus d'annonces
    static var sectionPopularCitiesSubtitle: String { tr("section_popular_cities_subtitle") }
    /// Annonces récentes
    static var sectionRecent: String { tr("section_recent") }
    /// Les dernières publiées
    static var sectionRecentSubtitle: String { tr("section_recent_subtitle") }
    /// Voir tout
    static var seeAll: String { tr("see_all") }
    /// %1$d annonces en ligne
    static func sellerListings(_ p1: Int) -> String { tr("seller_listings", p1) }
    /// Aucune annonce en ligne pour le moment
    static var sellerNoListings: String { tr("seller_no_listings") }
    /// Profil du vendeur
    static var sellerProfileTitle: String { tr("seller_profile_title") }
    /// ★ %1$.1f (%2$d)
    static func sellerRating(_ p1: Double, _ p2: Int) -> String { tr("seller_rating", p1, p2) }
    /// Partager
    static var share: String { tr("share") }
    /// Plus vus
    static var sortMostViewed: String { tr("sort_most_viewed") }
    /// Plus récent
    static var sortNewest: String { tr("sort_newest") }
    /// Plus ancien
    static var sortOldest: String { tr("sort_oldest") }
    /// Prix croissant
    static var sortPriceAsc: String { tr("sort_price_asc") }
    /// Prix décroissant
    static var sortPriceDesc: String { tr("sort_price_desc") }
    /// Pertinence
    static var sortRelevance: String { tr("sort_relevance") }
    /// Actives
    static var statActive: String { tr("stat_active") }
    /// Favoris reçus
    static var statFavorites: String { tr("stat_favorites") }
    /// Messages reçus
    static var statMessages: String { tr("stat_messages") }
    /// En attente
    static var statPending: String { tr("stat_pending") }
    /// Vendues
    static var statSold: String { tr("stat_sold") }
    /// Vues
    static var statViews: String { tr("stat_views") }
    /// Active
    static var statusActive: String { tr("status_active") }
    /// Expirée
    static var statusExpired: String { tr("status_expired") }
    /// En attente
    static var statusPending: String { tr("status_pending") }
    /// Refusée
    static var statusRejected: String { tr("status_rejected") }
    /// Vendue
    static var statusSold: String { tr("status_sold") }
    /// Catégorie
    static var suggestionCategory: String { tr("suggestion_category") }
    /// Annonce
    static var suggestionListing: String { tr("suggestion_listing") }
    /// Wilaya
    static var suggestionWilaya: String { tr("suggestion_wilaya") }
    /// La marketplace algérienne
    static var tagline: String { tr("tagline") }
    /// Répond vite
    static var trustFastResponder: String { tr("trust_fast_responder") }
    /// Recommandé
    static var trustRecommended: String { tr("trust_recommended") }
    /// Email vérifié
    static var trustVerified: String { tr("trust_verified") }
    /// Valeur trop élevée.
    static var validationAttrMax: String { tr("validation_attr_max") }
    /// Valeur trop basse.
    static var validationAttrMin: String { tr("validation_attr_min") }
    /// Nombre invalide.
    static var validationAttrNumber: String { tr("validation_attr_number") }
    /// Option invalide.
    static var validationAttrOption: String { tr("validation_attr_option") }
    /// Ce champ est obligatoire.
    static var validationAttrRequired: String { tr("validation_attr_required") }
    /// Texte trop long (200 caractères max.).
    static var validationAttrTextMax: String { tr("validation_attr_text_max") }
    /// La bio ne doit pas dépasser 500 caractères.
    static var validationBioMax: String { tr("validation_bio_max") }
    /// La catégorie est requise.
    static var validationCategoryRequired: String { tr("validation_category_required") }
    /// Saisissez les 6 chiffres du code.
    static var validationCode: String { tr("validation_code") }
    /// Indicatif invalide.
    static var validationCountryCode: String { tr("validation_country_code") }
    /// La description ne doit pas dépasser 5000 caractères.
    static var validationDescriptionMax: String { tr("validation_description_max") }
    /// La description doit contenir au moins 20 caractères.
    static var validationDescriptionMin: String { tr("validation_description_min") }
    /// Adresse email invalide.
    static var validationEmail: String { tr("validation_email") }
    /// Le message doit contenir au moins 10 caractères.
    static var validationMessageMin: String { tr("validation_message_min") }
    /// Le nom ne doit pas dépasser 50 caractères.
    static var validationNameMax: String { tr("validation_name_max") }
    /// Le nom doit contenir au moins 2 caractères.
    static var validationNameMin: String { tr("validation_name_min") }
    /// Au moins un chiffre.
    static var validationPasswordDigit: String { tr("validation_password_digit") }
    /// Au moins 8 caractères.
    static var validationPasswordMin: String { tr("validation_password_min") }
    /// Les mots de passe ne correspondent pas.
    static var validationPasswordMismatch: String { tr("validation_password_mismatch") }
    /// Mot de passe requis.
    static var validationPasswordRequired: String { tr("validation_password_required") }
    /// Au moins une majuscule.
    static var validationPasswordUppercase: String { tr("validation_password_uppercase") }
    /// Numéro mobile invalide (ex. 0550123456).
    static var validationPhone: String { tr("validation_phone") }
    /// Prix invalide.
    static var validationPriceInvalid: String { tr("validation_price_invalid") }
    /// Le prix ne peut pas être négatif.
    static var validationPriceNegative: String { tr("validation_price_negative") }
    /// Le sujet doit contenir au moins 3 caractères.
    static var validationSubjectMin: String { tr("validation_subject_min") }
    /// Le titre ne doit pas dépasser 100 caractères.
    static var validationTitleMax: String { tr("validation_title_max") }
    /// Le titre doit contenir au moins 5 caractères.
    static var validationTitleMin: String { tr("validation_title_min") }

    /// Toutes les clés du catalogue (test de parité).
    static let allKeys: [String] = [
        "account_data_title",
        "account_delete_google_confirm",
        "account_delete_google_hint",
        "alert_create",
        "alert_created",
        "alert_delete",
        "alert_duplicate",
        "alert_limit",
        "alerts_created_on",
        "alerts_empty",
        "alerts_empty_hint",
        "alerts_title",
        "all_categories",
        "app_name",
        "attr_no",
        "attr_yes",
        "auth_continue",
        "auth_email",
        "auth_forgot_body",
        "auth_forgot_button",
        "auth_forgot_link",
        "auth_forgot_sent_body",
        "auth_forgot_sent_title",
        "auth_forgot_title",
        "auth_google_button",
        "auth_have_account",
        "auth_login_button",
        "auth_login_link",
        "auth_login_subtitle",
        "auth_login_title",
        "auth_name",
        "auth_no_account",
        "auth_or",
        "auth_password",
        "auth_password_hide",
        "auth_password_rules",
        "auth_password_show",
        "auth_phone_optional",
        "auth_privacy_link",
        "auth_register_button",
        "auth_register_link",
        "auth_register_subtitle",
        "auth_register_title",
        "auth_retry_in",
        "auth_terms_link",
        "auth_terms_notice",
        "auth_verify_attempts_left",
        "auth_verify_body",
        "auth_verify_button",
        "auth_verify_code",
        "auth_verify_later",
        "auth_verify_resend",
        "auth_verify_resend_in",
        "auth_verify_resent",
        "auth_verify_success",
        "auth_verify_success_body",
        "auth_verify_title",
        "back",
        "cancel",
        "categories_all_row",
        "categories_empty",
        "categories_search_hint",
        "category_all_tile",
        "change_password_body",
        "change_password_confirm",
        "change_password_current",
        "change_password_mismatch",
        "change_password_new",
        "change_password_submit",
        "change_password_title",
        "chat_archive",
        "chat_archived",
        "chat_block_confirm_body",
        "chat_block_user",
        "chat_blocked_done",
        "chat_delete",
        "chat_delete_confirm_body",
        "chat_delete_message",
        "chat_deleted_user",
        "chat_deletion_window_expired",
        "chat_last_message_you",
        "chat_message_deleted",
        "chat_message_placeholder",
        "chat_more_actions",
        "chat_no_archives",
        "chat_no_conversations",
        "chat_no_conversations_desc",
        "chat_online",
        "chat_read",
        "chat_search_empty",
        "chat_search_placeholder",
        "chat_send",
        "chat_send_message_to",
        "chat_start_conversation",
        "chat_tab_archives",
        "chat_tab_conversations",
        "chat_typing",
        "chat_unarchive",
        "chat_unarchived",
        "chat_unblock_user",
        "chat_unblocked_done",
        "chat_unread",
        "chat_view_listing",
        "close",
        "contact_email",
        "contact_intro",
        "contact_message",
        "contact_message_sent",
        "contact_name",
        "contact_send",
        "contact_send_message",
        "contact_sent_body",
        "contact_sent_title",
        "contact_subject",
        "contact_template_1",
        "contact_template_2",
        "contact_template_3",
        "contact_title",
        "contact_to_seller",
        "currency_da",
        "delete_account_action",
        "delete_account_body",
        "delete_account_confirm_body",
        "delete_account_confirm_title",
        "delete_account_password",
        "delete_account_title",
        "detail_contact",
        "detail_description",
        "detail_expires_on",
        "detail_not_found_message",
        "detail_not_found_title",
        "detail_open_gallery",
        "detail_photo_counter",
        "detail_posted",
        "detail_reference",
        "detail_safety_bullet",
        "detail_safety_tip1",
        "detail_safety_tip2",
        "detail_safety_tip3",
        "detail_safety_tip4",
        "detail_safety_title",
        "detail_seller",
        "detail_show_phone",
        "detail_similar",
        "detail_status_expired",
        "detail_status_expired_desc",
        "detail_status_pending",
        "detail_status_pending_desc",
        "detail_status_rejected",
        "detail_status_rejected_desc",
        "detail_status_sold",
        "detail_status_sold_desc",
        "detail_views",
        "edit_profile_bio",
        "edit_profile_email_change_note",
        "edit_profile_save",
        "edit_profile_title",
        "empty_results",
        "empty_results_hint",
        "error_account_locked",
        "error_account_suspended",
        "error_admin_cannot_delete",
        "error_already_favorited",
        "error_already_reported",
        "error_annonce_unavailable",
        "error_cannot_block_self",
        "error_cannot_contact_self",
        "error_cannot_report_self",
        "error_cannot_respond_own_offer",
        "error_category_not_found",
        "error_code_cooldown",
        "error_code_expired",
        "error_daily_limit",
        "error_email_changed",
        "error_email_exists",
        "error_email_not_verified",
        "error_email_send_failed",
        "error_forbidden",
        "error_generic",
        "error_google_email_missing",
        "error_google_no_account",
        "error_google_reauth_mismatch",
        "error_google_sign_in",
        "error_google_unavailable",
        "error_incorrect_code",
        "error_incorrect_password",
        "error_invalid_attributes",
        "error_invalid_credentials",
        "error_invalid_data",
        "error_invalid_google_token",
        "error_max_images",
        "error_no_app",
        "error_no_code_pending",
        "error_no_open_offer",
        "error_no_phone",
        "error_not_found",
        "error_not_renewable",
        "error_offer_already_open",
        "error_offer_not_allowed",
        "error_offline",
        "error_own_review",
        "error_password_change_not_allowed",
        "error_photo_read",
        "error_post_rate_limited",
        "error_rate_limited",
        "error_renewal_limit",
        "error_review_not_eligible",
        "error_saved_search_empty",
        "error_server",
        "error_session_expired",
        "error_title",
        "error_upload_bad_format",
        "error_upload_failed",
        "error_upload_too_large",
        "error_user_blocked",
        "error_user_deleted",
        "error_user_not_found",
        "export_action",
        "export_body",
        "export_ready",
        "export_title",
        "favorite_add",
        "favorite_remove",
        "favorites_empty",
        "favorites_empty_hint",
        "favorites_title",
        "featured_badge",
        "filter_all",
        "filters_all",
        "filters_all_communes",
        "filters_all_wilayas",
        "filters_apply",
        "filters_attr_max",
        "filters_attr_min",
        "filters_attr_value",
        "filters_clear_all",
        "filters_featured_chip",
        "filters_featured_only",
        "filters_location",
        "filters_price",
        "filters_price_between",
        "filters_price_from",
        "filters_price_max",
        "filters_price_min",
        "filters_price_to",
        "filters_range_max",
        "filters_range_min",
        "filters_remove",
        "filters_reset",
        "filters_sort",
        "filters_subcategories",
        "filters_title",
        "filters_yes_only",
        "home_browse_all",
        "home_cta_subtitle",
        "home_cta_title",
        "home_for_you",
        "home_for_you_subtitle",
        "home_trending",
        "home_trending_subtitle",
        "language_ar",
        "language_en",
        "language_fr",
        "language_hint",
        "language_legacy_hint",
        "language_open_settings",
        "language_system",
        "language_title",
        "legal_about",
        "legal_account_deletion",
        "legal_contact",
        "legal_notice",
        "legal_opens_browser",
        "legal_privacy",
        "legal_terms",
        "legal_title",
        "legal_version",
        "loading",
        "login_required_body",
        "login_required_title",
        "member_since",
        "moderation_reason",
        "my_listing_delete",
        "my_listing_delete_confirm_body",
        "my_listing_delete_confirm_title",
        "my_listing_deleted",
        "my_listing_edit",
        "my_listing_mark_sold",
        "my_listing_renew",
        "my_listing_renewed",
        "my_listing_sold_confirm_body",
        "my_listing_sold_confirm_btn",
        "my_listing_sold_confirm_title",
        "my_listing_sold_done",
        "my_listings_title",
        "nav_home",
        "nav_listings",
        "nav_messages",
        "nav_post",
        "nav_profile",
        "notification_delete",
        "notification_type_annonce_approved",
        "notification_type_annonce_expired",
        "notification_type_annonce_rejected",
        "notification_type_favorite_price_drop",
        "notification_type_favorite_sold",
        "notification_type_message",
        "notification_type_offer_accepted",
        "notification_type_offer_counter",
        "notification_type_offer_received",
        "notification_type_offer_rejected",
        "notification_type_review",
        "notification_type_search_alert",
        "notifications_empty",
        "notifications_mark_all_read",
        "notifications_title",
        "offer_accept",
        "offer_accepted",
        "offer_already_open_notice",
        "offer_amount_placeholder",
        "offer_asking_price",
        "offer_counter",
        "offer_counter_received",
        "offer_counter_sent",
        "offer_counter_title",
        "offer_current",
        "offer_decline",
        "offer_declined",
        "offer_helper",
        "offer_invalid_amount",
        "offer_make",
        "offer_received",
        "offer_send",
        "offer_sent",
        "offer_waiting_response",
        "offer_your_offer",
        "offline_banner",
        "post_ad_description",
        "post_ad_description_placeholder",
        "post_ad_title",
        "post_ad_title_placeholder",
        "post_analyzing",
        "post_another",
        "post_back",
        "post_char_count",
        "post_choose_category",
        "post_choose_subcategory",
        "post_clear_selection",
        "post_commune",
        "post_discard_confirm",
        "post_discard_keep",
        "post_discard_message",
        "post_discard_title",
        "post_edit_pending_warning",
        "post_edit_step",
        "post_edit_title",
        "post_expiration_notice",
        "post_location_hint",
        "post_more_details",
        "post_my_listings",
        "post_next",
        "post_photo_camera",
        "post_photo_count",
        "post_photo_gallery",
        "post_photo_main",
        "post_photo_make_main",
        "post_photo_remove",
        "post_photo_retry",
        "post_photos_failed_hint",
        "post_photos_hint",
        "post_photos_limit",
        "post_price",
        "post_price_fixed",
        "post_price_free",
        "post_price_negotiable",
        "post_price_negotiable_hint",
        "post_price_not_set",
        "post_price_placeholder",
        "post_price_type",
        "post_publish",
        "post_review_no_location",
        "post_review_no_photos",
        "post_review_phone_hidden",
        "post_review_phone_shown",
        "post_review_subtitle",
        "post_review_title",
        "post_save",
        "post_select_commune",
        "post_select_parent_first",
        "post_select_wilaya",
        "post_show_phone",
        "post_show_phone_hint",
        "post_step_attributes",
        "post_step_category",
        "post_step_details",
        "post_step_location",
        "post_step_of",
        "post_step_photos",
        "post_step_review",
        "post_success_approved",
        "post_success_desc",
        "post_success_pending_review",
        "post_success_published",
        "post_success_title",
        "post_title",
        "post_updated_pending",
        "post_updated_saved",
        "post_updated_title",
        "post_view_listing",
        "post_wilaya",
        "price_dzd",
        "price_free",
        "price_negotiable",
        "price_on_request",
        "profile_account_data",
        "profile_alerts",
        "profile_change_password",
        "profile_edit",
        "profile_favorites",
        "profile_language",
        "profile_logout",
        "profile_logout_confirm_body",
        "profile_logout_confirm_title",
        "profile_my_listings",
        "profile_recommended",
        "profile_stats_title",
        "profile_title",
        "profile_unverified",
        "profile_verified",
        "profile_verify_action",
        "profile_verify_banner",
        "push_channel_account",
        "push_channel_account_desc",
        "push_channel_listings",
        "push_channel_listings_desc",
        "push_channel_messages",
        "push_channel_messages_desc",
        "push_channel_offers",
        "push_channel_offers_desc",
        "rating_out_of_five",
        "report_action",
        "report_details",
        "report_details_placeholder",
        "report_reason",
        "report_reason_duplicate",
        "report_reason_fraud",
        "report_reason_inappropriate",
        "report_reason_other",
        "report_reason_spam",
        "report_sent",
        "report_submit",
        "report_title",
        "report_user_action",
        "report_user_hint",
        "report_user_title",
        "reset_confirm_password",
        "reset_invalid_link",
        "reset_new_password",
        "reset_submit",
        "reset_subtitle",
        "reset_success_body",
        "reset_success_title",
        "reset_title",
        "results_count",
        "retry",
        "review_anonymous",
        "review_comment",
        "review_comment_placeholder",
        "review_edit",
        "review_leave",
        "review_rating",
        "review_send",
        "review_sent",
        "review_star",
        "reviews_empty",
        "reviews_title",
        "search_clear",
        "search_clear_history",
        "search_did_you_mean",
        "search_hint",
        "search_history",
        "section_categories",
        "section_featured",
        "section_featured_subtitle",
        "section_popular_cities",
        "section_popular_cities_subtitle",
        "section_recent",
        "section_recent_subtitle",
        "see_all",
        "seller_listings",
        "seller_no_listings",
        "seller_profile_title",
        "seller_rating",
        "share",
        "sort_most_viewed",
        "sort_newest",
        "sort_oldest",
        "sort_price_asc",
        "sort_price_desc",
        "sort_relevance",
        "stat_active",
        "stat_favorites",
        "stat_messages",
        "stat_pending",
        "stat_sold",
        "stat_views",
        "status_active",
        "status_expired",
        "status_pending",
        "status_rejected",
        "status_sold",
        "suggestion_category",
        "suggestion_listing",
        "suggestion_wilaya",
        "tagline",
        "trust_fast_responder",
        "trust_recommended",
        "trust_verified",
        "validation_attr_max",
        "validation_attr_min",
        "validation_attr_number",
        "validation_attr_option",
        "validation_attr_required",
        "validation_attr_text_max",
        "validation_bio_max",
        "validation_category_required",
        "validation_code",
        "validation_country_code",
        "validation_description_max",
        "validation_description_min",
        "validation_email",
        "validation_message_min",
        "validation_name_max",
        "validation_name_min",
        "validation_password_digit",
        "validation_password_min",
        "validation_password_mismatch",
        "validation_password_required",
        "validation_password_uppercase",
        "validation_phone",
        "validation_price_invalid",
        "validation_price_negative",
        "validation_subject_min",
        "validation_title_max",
        "validation_title_min",
    ]

    /// Clés à variantes de pluriel.
    static let pluralKeys: [String] = [
        "auth_verify_attempts_left",
        "detail_views",
        "results_count",
        "review_star",
        "seller_listings",
    ]
}

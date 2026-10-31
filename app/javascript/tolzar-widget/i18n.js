// Tolzar widget strings, written by us, in the six languages Tolzar ships (en, ar, de, fr, es, pt). Arabic is
// right to left. Unknown languages fall back to English.

export const STRINGS = {
  en: {
    PLACEHOLDER: 'Write a message…',
    SEND: 'Send',
    CLOSE: 'Close chat',
    MESSAGES: 'Messages',
    TYPING: 'Typing…',
    SENDING: 'Sending…',
    FAILED: 'Not sent. Tap send to try again.',
    LOAD_FAILED: 'Could not load the chat. Check your connection.',
    RESOLVED: 'This conversation was closed.',
    REPLY_TIME: 'We usually reply within a few minutes.',
  },
  ar: {
    PLACEHOLDER: 'اكتب رسالة…',
    SEND: 'إرسال',
    CLOSE: 'إغلاق المحادثة',
    MESSAGES: 'الرسائل',
    TYPING: 'يكتب…',
    SENDING: 'جارٍ الإرسال…',
    FAILED: 'لم تُرسل. اضغط إرسال للمحاولة مرة أخرى.',
    LOAD_FAILED: 'تعذّر تحميل المحادثة. تحقّق من الاتصال.',
    RESOLVED: 'تم إغلاق هذه المحادثة.',
    REPLY_TIME: 'نردّ عادةً خلال دقائق.',
  },
  de: {
    PLACEHOLDER: 'Nachricht schreiben…',
    SEND: 'Senden',
    CLOSE: 'Chat schließen',
    MESSAGES: 'Nachrichten',
    TYPING: 'Schreibt…',
    SENDING: 'Wird gesendet…',
    FAILED: 'Nicht gesendet. Zum Wiederholen auf Senden tippen.',
    LOAD_FAILED:
      'Der Chat konnte nicht geladen werden. Bitte Verbindung prüfen.',
    RESOLVED: 'Dieses Gespräch wurde beendet.',
    REPLY_TIME: 'Wir antworten meist innerhalb weniger Minuten.',
  },
  fr: {
    PLACEHOLDER: 'Écrivez un message…',
    SEND: 'Envoyer',
    CLOSE: 'Fermer la discussion',
    MESSAGES: 'Messages',
    TYPING: 'En train d’écrire…',
    SENDING: 'Envoi…',
    FAILED: 'Non envoyé. Touchez Envoyer pour réessayer.',
    LOAD_FAILED:
      'Impossible de charger la discussion. Vérifiez votre connexion.',
    RESOLVED: 'Cette conversation est terminée.',
    REPLY_TIME: 'Nous répondons en général en quelques minutes.',
  },
  es: {
    PLACEHOLDER: 'Escribe un mensaje…',
    SEND: 'Enviar',
    CLOSE: 'Cerrar el chat',
    MESSAGES: 'Mensajes',
    TYPING: 'Escribiendo…',
    SENDING: 'Enviando…',
    FAILED: 'No enviado. Toca Enviar para reintentar.',
    LOAD_FAILED: 'No se pudo cargar el chat. Revisa tu conexión.',
    RESOLVED: 'Esta conversación se cerró.',
    REPLY_TIME: 'Solemos responder en pocos minutos.',
  },
  pt: {
    PLACEHOLDER: 'Escreva uma mensagem…',
    SEND: 'Enviar',
    CLOSE: 'Fechar o chat',
    MESSAGES: 'Mensagens',
    TYPING: 'A escrever…',
    SENDING: 'A enviar…',
    FAILED: 'Não enviada. Toque em Enviar para tentar de novo.',
    LOAD_FAILED: 'Não foi possível carregar o chat. Verifique a ligação.',
    RESOLVED: 'Esta conversa foi encerrada.',
    REPLY_TIME: 'Costumamos responder em poucos minutos.',
  },
};

const RTL = new Set(['ar', 'he', 'fa', 'ur']);

export function lang(locale) {
  const base = String(locale || 'en')
    .toLowerCase()
    .replace('_', '-')
    .split('-')[0];
  return STRINGS[base] ? base : 'en';
}

export function t(locale, key) {
  return STRINGS[lang(locale)][key] ?? STRINGS.en[key] ?? key;
}

export function direction(locale) {
  return RTL.has(
    String(locale || '')
      .toLowerCase()
      .split(/[-_]/)[0]
  )
    ? 'rtl'
    : 'ltr';
}

// Tolzar widget: the pre-chat form from the inbox's settings (pre_chat_fields: name, label, type, required,
// enabled, field_type standard | contact_attribute | conversation_attribute). validate() returns the errors by
// field; toRequest() builds the conversation create body (contact, first message, custom attributes).

const STANDARD = {
  emailAddress: 'email',
  fullName: 'name',
  phoneNumber: 'phone_number',
};
const EMAIL = /^[^@\s]{1,64}@[^@\s]{1,190}\.[^@\s]{2,24}$/;
const PHONE = /^\+[1-9]\d{6,14}$/;

export function fields(options) {
  return (options?.pre_chat_fields || []).filter(f => f && f.enabled);
}

export function needed({ enabled, options, hasMessages }) {
  return Boolean(enabled) && !hasMessages && fields(options).length > 0;
}

export function validate(list, values, message) {
  const errors = {};
  list.forEach(f => {
    const v = String(values[f.name] ?? '').trim();
    if (f.required && !v) errors[f.name] = 'REQUIRED';
    else if (
      v &&
      (f.type === 'email' || f.name === 'emailAddress') &&
      !EMAIL.test(v)
    )
      errors[f.name] = 'EMAIL';
    else if (
      v &&
      f.name === 'phoneNumber' &&
      !PHONE.test(v.replace(/[\s-]/g, ''))
    )
      errors[f.name] = 'PHONE';
  });
  if (!String(message || '').trim()) errors.message = 'REQUIRED';
  return errors;
}

export function toRequest(list, values, message) {
  const contact = { custom_attributes: {} };
  const conversationAttributes = {};
  list.forEach(f => {
    const raw = values[f.name];
    if (raw == null || String(raw).trim() === '') return;
    const v = f.type === 'checkbox' ? Boolean(raw) : String(raw).trim();
    if (f.field_type === 'conversation_attribute')
      conversationAttributes[f.name] = v;
    else if (STANDARD[f.name])
      contact[STANDARD[f.name]] =
        f.name === 'phoneNumber' ? v.replace(/[\s-]/g, '') : v;
    else contact.custom_attributes[f.name] = v;
  });
  return {
    contact,
    message: {
      content: String(message).trim(),
      timestamp: new Date().toString(),
    },
    custom_attributes: conversationAttributes,
  };
}

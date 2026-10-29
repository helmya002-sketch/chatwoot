import wootConstants from 'dashboard/constants/globals';
import wootAPI from './apiClient';

// Tolzar: no third-party testimonials feed; the signup page shows none.
export const getTestimonialContent = () =>
  wootConstants.TESTIMONIAL_URL
    ? wootAPI.get(wootConstants.TESTIMONIAL_URL)
    : Promise.resolve({ data: [] });

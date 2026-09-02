import * as React from 'react';
import { Notice } from '@donerup/ui';

export const OperationsNotice = () => (
  <Notice>
    <strong>IT Operations notice.</strong> The password reset rollout is paused
    outside DACH and will be re-planned for the coming quarter. Sign in is
    unaffected. Report builder templates are maintained centrally — raise
    template changes with the service desk.
  </Notice>
);

export const Short = () => (
  <Notice>
    <strong>Scheduled maintenance.</strong> The portal is read-only on Sundays
    between 02:00 and 04:00 CET.
  </Notice>
);

import * as React from 'react';
import { LoginHero, LoginStage, Card, Field, Button, Fineprint, BuildTag } from '@donerup/ui';

export const SignInScreen = () => (
  <div>
    <LoginHero />
    <LoginStage>
      <Card title="Sign in" subtitle="Donerup Restaurant Group — Employee Directory">
        <Field id="username" label="Username" />
        <Field id="password" label="Password" type="password" />
        <Button>Sign in</Button>
      </Card>
      <Fineprint>
        Authenticating against the corporate LDAP directory.
        <br />
        Contact IT Service Desk for access requests.
      </Fineprint>
      <BuildTag>
        Portal 2026.2.4 · Scheduled maintenance Sundays 02:00–04:00 CET
        <br />© 2026 Donerup Restaurant Group
      </BuildTag>
    </LoginStage>
  </div>
);

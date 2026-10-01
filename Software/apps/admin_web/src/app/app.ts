import { AfterViewChecked, ChangeDetectionStrategy, Component, inject } from '@angular/core';
import { AdminAuthService } from './core/admin-auth.service';
import { AccessComponent } from './features/access.component';
import { AdminShellComponent } from './layout/admin-shell.component';
@Component({
  selector: 'app-root',
  imports: [AccessComponent, AdminShellComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `@if (auth.admin(); as admin) {
      <app-admin-shell [admin]="admin" (logout)="auth.logout()" />
    } @else {
      <app-access />
    }`,
})
export class App implements AfterViewChecked {
  readonly auth = inject(AdminAuthService);
  ngAfterViewChecked() {
    window.lucide?.createIcons({ attrs: { 'stroke-width': 2.2 } });
  }
}

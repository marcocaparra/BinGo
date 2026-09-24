import { AfterViewChecked, ChangeDetectionStrategy, Component, signal } from '@angular/core';
import { AdminRole } from './admin-access';
import { AccessComponent } from './features/access.component';
import { AdminShellComponent } from './layout/admin-shell.component';
@Component({
  selector: 'app-root',
  imports: [AccessComponent, AdminShellComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `@if (authenticated()) {
      <app-admin-shell
        [role]="role()"
        (roleChange)="role.set($event)"
        (logout)="authenticated.set(false)"
      />
    } @else {
      <app-access (entered)="enter($event)" />
    }`,
})
export class App implements AfterViewChecked {
  readonly authenticated = signal(false);
  readonly role = signal<AdminRole>('ADMIN_C');
  enter(role: AdminRole) {
    this.role.set(role);
    this.authenticated.set(true);
    window.scrollTo(0, 0);
  }
  ngAfterViewChecked() {
    window.lucide?.createIcons({ attrs: { 'stroke-width': 2.2 } });
  }
}

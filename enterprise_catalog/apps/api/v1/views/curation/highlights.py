from edx_rbac.mixins import PermissionRequiredForListingMixin
from rest_framework import viewsets
from rest_framework.renderers import JSONRenderer

from enterprise_catalog.apps.api.v1.pagination import (
    PageNumberWithSizePagination,
)
from enterprise_catalog.apps.api.v1.serializers import (
    EnterpriseCurationSerializer,
)
from enterprise_catalog.apps.catalog.constants import (
    ENTERPRISE_CATALOG_ADMIN_ROLE,
    PERMISSION_HAS_LEARNER_ACCESS,
)
from enterprise_catalog.apps.api.v1.views.base import BaseViewSet
from enterprise_catalog.apps.catalog.models import (
    EnterpriseCatalogRoleAssignment,
)
from enterprise_catalog.apps.catalog.rules import (
    enterprises_with_admin_access,
    has_access_to_all_enterprises,
)
from enterprise_catalog.apps.curation.models import EnterpriseCurationConfig


class EnterpriseCurationConfigReadOnlyViewSet(PermissionRequiredForListingMixin, BaseViewSet, viewsets.ModelViewSet):
    """ Viewset for listing and retrieving EnterpriseCurationConfigs. """
    renderer_classes = [JSONRenderer]
    permission_required = PERMISSION_HAS_LEARNER_ACCESS
    queryset = EnterpriseCurationConfig.objects.all()
    serializer_class = EnterpriseCurationSerializer

    # Fields required for controlling access in the `list()` action
    list_lookup_field = 'enterprise_uuid'
    allowed_roles = [ENTERPRISE_CATALOG_ADMIN_ROLE]
    role_assignment_class = EnterpriseCatalogRoleAssignment
    base_queryset = EnterpriseCurationConfig.objects.all()

    def get_permission_object(self):
        """
        Retrieves the apporpriate object to use during edx-rbac's permission checks.

        This object is passed to the rule predicate(s).
        """
        return self.kwargs.get('enterprise_uuid')

import collections
import json
from logging import getLogger
from uuid import uuid4

from config_models.models import ConfigurationModel
from django.conf import settings
from django.db import IntegrityError, OperationalError, models, transaction
from django.db.models import Q
from django.db.models.query import QuerySet
from django.utils.functional import cached_property
from django.utils.translation import gettext as _
from edx_rbac.models import UserRole, UserRoleAssignment
from jsonfield.encoder import JSONEncoder
from jsonfield.fields import JSONField
from model_utils.models import TimeStampedModel
from simple_history.models import HistoricalRecords

from enterprise_catalog.apps.catalog.models import (
    ContentMetadata,
    EnterpriseCatalog,
)


class EnterpriseCurationConfig(TimeStampedModel):
    """
    Top-level container for all curations related to an enterprise.
    What's nice about this model:
    * Top-level container to hold anything related to catalog curation for an enterprise
    (there might be a time where we want types of curation besides highlights).
    * Gives us place to grow horizontally for fields related to a single enterprise's curation behavior.
    """
    uuid = models.UUIDField(
        primary_key=True,
        default=uuid4,
        editable=False,
    )
    title = models.CharField(
        max_length=255,
        blank=False,
        null=False,
    )
    enterprise_uuid = models.UUIDField(
        blank=False,
        null=False,
        unique=True,
        db_index=True,
    )
    is_highlight_feature_active = models.BooleanField(
        null=False,
        default=True,
    )
    history = HistoricalRecords()

    class Meta:
        verbose_name = _("Enterprise Curation")
        verbose_name_plural = _("Enterprise Curations")
        app_label = 'curation'


class HighlightSet(TimeStampedModel):
    """
    One enterprise curation may produce multiple catalog highlight sets.
    What's nice about this model:
    * Could have multiple highlight sets per customer.
    * Could have multiple highlight sets per catalog (maybe we don't want to allow this now, but
    we might want it for highlight cohorts later).
    """
    uuid = models.UUIDField(
        primary_key=True,
        default=uuid4,
        editable=False,
    )
    title = models.CharField(
        max_length=255,
        blank=False,
        null=False,
    )
    enterprise_curation = models.ForeignKey(
        EnterpriseCurationConfig,
        blank=False,
        null=False,
        related_name='catalog_highlights',
        on_delete=models.deletion.CASCADE,
    )
    # can the learners see it?
    is_published = models.BooleanField(
        default=False,
        null=False,        
    )
    history = HistoricalRecords()

    class Meta:
        app_label = 'curation'


class HighlightedContent(TimeStampedModel):
    """
    One HighlightSet can contain 0 or more HighlightedContent records.

    What's nice about this model:
    * Can highlight any kind of content that lives in enterprise-catalog 
    (courses, programs, or course runs if necessary - though maybe we want to block that?)
    * Can use counts() in views that add highlights to enforce a max highlight content count per set.

    TODO: is there a way to easily record which catalog(s) were applicable for the enterprise
    when some content was added to the highlight set?
    """
    uuid = models.UUIDField(
        primary_key=True,
        default=uuid4,
        editable=False,
    )
    catalog_highlight_set = models.ForeignKey(
        HighlightSet,
        blank=False,
        null=True,
        related_name='highlighted_content',
        on_delete=models.deletion.CASCADE,
    )
    content_metadata = models.ForeignKey(
        ContentMetadata,
        blank=False,
        null=True,
        related_name='highlighted_content',
        on_delete=models.deletion.CASCADE,
    )
    history = HistoricalRecords()

    class Meta:
        app_label = 'curation'
        unique_together = ('catalog_highlight_set', 'content_metadata')
